# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/graphql/datastore_response/search_response"
require "elastic_graph/graphql/query_details_tracker"
require "elastic_graph/support/threading"

module ElasticGraph
  class GraphQL
    # Responsible for routing datastore search requests to the appropriate cluster and index.
    class DatastoreSearchRouter
      def initialize(
        datastore_clients_by_name:,
        logger:,
        monotonic_clock:,
        config:
      )
        @datastore_clients_by_name = datastore_clients_by_name
        @logger = logger
        @monotonic_clock = monotonic_clock
        @config = config
      end

      # Sends the datastore a multi-search request based on the given queries.
      # Returns a hash of responses keyed by the query.
      def msearch(queries, query_tracker: QueryDetailsTracker.empty)
        DatastoreQuery.perform(queries) do |header_body_tuples_by_query|
          # Here we set a client-side timeout, which causes the client to give up and close the connection.
          # According to [1]--"We have a new way to cancel search requests efficiently from the client
          # in 7.4 (by closing the underlying http channel)"--this should cause the server to stop
          # executing the search, and more importantly, gives us a strictly enforced timeout.
          #
          # In addition, the datastore supports a `timeout` option on a search body, but this timeout is
          # "best effort", applies to each shard (and not to the overall search request), and only interrupts
          # certain kinds of operations. [2] and [3] below have more info.
          #
          # Note that I have not been able to observe this `timeout` on a search body ever working
          # as documented. In our test suite, none of the slow queries I have tried (both via
          # slow aggregation query and a slow script) have ever aborted early when that option is
          # set. In Kibana in production, @bsorbo observed it aborting a `search` request early
          # (but not necessarily an `msearch` request...), but even then, the response said `timed_out: false`!
          # Other people ([4]) have reported observing timeout having no effect on msearch requests.
          #
          # So, the client-side timeout is the main one we want here, and for now we are not using the
          # datastore search `timeout` option at all.
          #
          # For more info, see:
          #
          # [1] https://github.com/elastic/elasticsearch/issues/47716
          # [2] https://github.com/elastic/elasticsearch/pull/51858
          # [3] https://www.elastic.co/guide/en/elasticsearch/guide/current/_search_options.html#_timeout_2
          # [4] https://discuss.elastic.co/t/timeouts-ignored-in-multisearch/23673

          # Unfortunately, the Elasticsearch/OpenSearch clients don't support setting a per-request client-side timeout,
          # even though Faraday (the underlying HTTP client) does. To work around this, we pass our desired
          # timeout in a specific header that the `SupportTimeouts` Faraday middleware will use.
          headers = {TIMEOUT_MS_HEADER => msearch_request_timeout_from(queries)&.to_s}.compact

          queries_and_header_body_tuples_by_datastore_client = header_body_tuples_by_query.group_by do |(query, header_body_tuples)|
            @datastore_clients_by_name.fetch(query.cluster_name)
          end

          datastore_query_started_at = @monotonic_clock.now_in_ms

          server_took_and_results = Support::Threading.parallel_map(queries_and_header_body_tuples_by_datastore_client) do |datastore_client, query_and_header_body_tuples_for_cluster|
            queries_for_cluster, header_body_tuples = query_and_header_body_tuples_for_cluster.transpose
            msearch_body = header_body_tuples.flatten(1)
            response = datastore_client.msearch(body: msearch_body, headers: headers)
            debug_query(query: msearch_body, response: response)
            ordered_responses = response.fetch("responses")
            [response["took"], queries_for_cluster.zip(ordered_responses)]
          end

          queried_shard_count = server_took_and_results.reduce(0) do |outer_accum, (_, queries_and_responses)|
            outer_accum + queries_and_responses.reduce(0) do |inner_accum, (_, response)|
              inner_accum + (response.dig("_shards", "total") || 0)
            end
          end

          query_tracker.record_datastore_query_metrics(
            client_duration_ms: @monotonic_clock.now_in_ms - datastore_query_started_at,
            server_duration_ms: server_took_and_results.map(&:first).compact.max,
            queried_shard_count: queried_shard_count
          )

          server_took_and_results.flat_map(&:last).to_h.tap do |responses_by_query|
            log_shard_failure_if_necessary(responses_by_query)
            raise_search_failed_if_any_failures(responses_by_query)
          end
        end
      end

      private

      # Prefix tests with `DEBUG_QUERY=1 ...` or run `export DEBUG_QUERY=1` to print the actual
      # Elasticsearch/OpenSearch query and response. This is particularly useful for adding new specs.
      def debug_query(**debug_messages)
        return unless ::ENV["DEBUG_QUERY"]

        formatted_messages = debug_messages.map do |key, msg|
          "#{key.to_s.upcase}:\n#{::JSON.pretty_generate(msg)}\n"
        end.join("\n")
        puts "\n#{formatted_messages}\n\n"
      end

      def msearch_request_timeout_from(queries)
        return nil unless (min_query_deadline = queries.map(&:monotonic_clock_deadline).compact.min)

        (min_query_deadline - @monotonic_clock.now_in_ms).tap do |timeout|
          if timeout <= 0
            raise Errors::RequestExceededDeadlineError, "It is already #{timeout.abs} ms past the search deadline."
          end
        end
      end

      def raise_search_failed_if_any_failures(responses_by_query)
        failures = responses_by_query.each_with_index.select { |(_query, response), _index| response["error"] }
        return if failures.empty?

        formatted_failures = failures.map do |(query, response), index|
          raise_execution_exception_for_known_public_error(response)

          # Note: we intentionally omit the body of the request here, because it could contain PII
          # or other sensitive values that we don't want logged.
          <<~ERROR
            #{index + 1}) Header: #{::JSON.generate(query.to_datastore_msearch_header)}
            #{response.fetch("error").inspect}"
            On cluster: #{query.cluster_name}
          ERROR
        end.join("\n\n")

        raise Errors::SearchFailedError, "Got #{failures.size} search failure(s):\n\n#{formatted_failures}"
      end

      # In general, when we receive a datastore response indicating a search failed, we raise
      # `Errors::SearchFailedError` which translates into a `500 Internal Server Error`. That's
      # appropriate for transient errors (particularly when there's nothing the client can do about
      # it) but for non-transient errors that the client can do something about, we'd like to provide
      # a friendlier error. This method handles those cases.
      #
      # GraphQL::ExecutionError is automatically translated into a nice error response.
      def raise_execution_exception_for_known_public_error(response)
        if response.dig("error", "caused_by", "type") == "too_many_buckets_exception"
          max_buckets = response.dig("error", "caused_by", "max_buckets")
          raise ::GraphQL::ExecutionError, "Aggregation query produces too many groupings. " \
            "Reduce the grouping cardinality to less than #{max_buckets} and try again."
        end
      end

      # Examine successful query responses and log any shard failure they encounter
      def log_shard_failure_if_necessary(responses_by_query)
        shard_failures = responses_by_query.each_with_index.select do |(query, response), query_numeric_index|
          (200..299).cover?(response["status"]) && response["_shards"]["failed"] != 0
        end

        unless shard_failures.empty?
          formatted_failures = shard_failures.map do |(query, response), query_numeric_index|
            "Query #{query_numeric_index + 1} against index `#{query.search_index_expression}` on cluster `#{query.cluster_name}`}: " +
              JSON.pretty_generate(response["_shards"])
          end.join("\n\n")

          formatted_shard_failures = "The following queries have failed shards: \n\n#{formatted_failures}"
          @logger.warn(formatted_shard_failures)
        end
      end
    end
  end
end
