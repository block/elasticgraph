# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/client"
require "elastic_graph/graphql/query_details_tracker"
require "elastic_graph/support/hash_util"

module ElasticGraph
  class GraphQL
    # Responsible for executing queries.
    class QueryExecutor
      # @dynamic schema
      attr_reader :schema

      def initialize(schema:, monotonic_clock:, logger:, slow_query_threshold_ms:)
        @schema = schema
        @monotonic_clock = monotonic_clock
        @logger = logger
        @slow_query_threshold_ms = slow_query_threshold_ms
      end

      # Executes the given `query_string` using the provided `variables`.
      #
      # `timeout_in_ms` can be provided to limit how long the query runs for. If the timeout
      # is exceeded, `Errors::RequestExceededDeadlineError` will be raised. Note that `timeout_in_ms`
      # does not provide an absolute guarantee that the query will take no longer than the
      # provided value; it is only used to halt datastore queries. In process computation
      # can make the total query time exceeded the specified timeout.
      #
      # `context` is merged into the context hash passed to the resolvers.
      def execute(
        query_string,
        client: Client::ANONYMOUS,
        variables: {},
        timeout_in_ms: nil,
        operation_name: nil,
        context: {},
        start_time_in_ms: @monotonic_clock.now_in_ms
      )
        # Before executing the query, prune any null-valued variable fields. This means we
        # treat `foo: null` the same as if `foo` was unmentioned. With certain clients (e.g.
        # code-gen'd clients in a statically typed language), it is non-trivial to avoid
        # mentioning variable fields they aren't using. It makes it easier to evolve the
        # schema if we ignore null-valued fields rather than potentially returning an error
        # due to a null-valued field referencing an undefined schema element.
        variables = ElasticGraph::Support::HashUtil.recursively_prune_nils_from(variables)

        query_tracker = QueryDetailsTracker.empty

        query, result = build_and_execute_query(
          query_string: query_string,
          variables: variables,
          operation_name: operation_name,
          client: client,
          context: context.merge({
            monotonic_clock_deadline: timeout_in_ms&.+(start_time_in_ms),
            elastic_graph_query_tracker: query_tracker
          }.compact)
        )

        unless result.to_h.fetch("errors", []).empty?
          @logger.error <<~EOS
            Query #{query.operation_name}[1] for client #{client.description} resulted in errors[2].

            [1] #{full_description_of(query)}

            [2] #{::JSON.pretty_generate(result.to_h.fetch("errors"))}
          EOS
        end

        duration = @monotonic_clock.now_in_ms - start_time_in_ms

        # Note: I also wanted to log the sanitized query if `result` has `errors`, but `GraphQL::Query#sanitized_query`
        # returns `nil` on an invalid query, and I don't want to risk leaking PII by logging the raw query string, so
        # we don't log any form of the query in that case.
        if duration > @slow_query_threshold_ms
          @logger.warn "Query #{query.operation_name} for client #{client.description} with shard routing values " \
            "#{query_tracker.shard_routing_values.sort.inspect} and search index expressions #{query_tracker.search_index_expressions.sort.inspect} took longer " \
            "(#{duration} ms) than the configured slow query threshold (#{@slow_query_threshold_ms} ms). " \
            "Sanitized query:\n\n#{query.sanitized_query_string}"
        end

        unless client == Client::ELASTICGRAPH_INTERNAL
          log_data = {
            "message_type" => "ElasticGraphQueryExecutorQueryDuration",
            "client" => client.name,
            "query_fingerprint" => fingerprint_for(query),
            "query_name" => query.operation_name,
            "duration_ms" => duration,
            # How long the datastore queries took according to what the datastore itself reported.
            "datastore_server_duration_ms" => query_tracker.datastore_query_server_duration_ms,
            # An estimate for how much overhead ElasticGraph added on top of how long the datastore took.
            # This is based on the duration, excluding how long the datastore calls took from the client side
            # (e.g. accounting for network latency, serialization time, etc)
            "elasticgraph_overhead_ms" => duration - query_tracker.datastore_query_client_duration_ms,
            # An estimate for the time spent on transport (network latency, JSON serialization, etc).
            "datastore_request_transport_duration_ms" => query_tracker.datastore_request_transport_duration_ms,
            # How many datastore shards were queried, in total. This is a measure of how much load the query caused on the datastore.
            "queried_shard_count" => query_tracker.queried_shard_count,
            # According to https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/FilterAndPatternSyntax.html#metric-filters-extract-json,
            # > Value nodes can be strings or numbers...If a property selector points to an array or object, the metric filter won't match the log format.
            # So, to allow flexibility to deal with cloud watch metric filters, we coerce these values to a string here.
            "unique_shard_routing_values" => query_tracker.shard_routing_values.sort.join(", "),
            # We also include the count of shard routing values, to make it easier to search logs
            # for the case of no shard routing values.
            "unique_shard_routing_value_count" => query_tracker.shard_routing_values.count,
            "unique_search_index_expressions" => query_tracker.search_index_expressions.sort.join(", "),
            # Indicates how many requests we sent to the datastore to satisfy the GraphQL query.
            "datastore_request_count" => query_tracker.query_counts_per_datastore_request.size,
            # Indicates how many individual datastore queries there were. One datastore request
            # can contain many queries (since we use `msearch`), so these counts can be different.
            "datastore_query_count" => query_tracker.query_counts_per_datastore_request.sum,
            "over_slow_threshold" => (duration > @slow_query_threshold_ms).to_s,
            "slo_result" => slo_result_for(query, duration)
          }

          # Merge in any extension-provided data
          log_data.merge!(query_tracker.extension_data)

          @logger.info(log_data)
        end

        result
      end

      private

      # Note: this is designed so that `elasticgraph-query_registry` can hook into this method. It needs to be able
      # to override how the query is built and executed.
      def build_and_execute_query(query_string:, variables:, operation_name:, context:, client:)
        query = @schema.new_graphql_query(
          query_string,
          variables: variables,
          operation_name: operation_name,
          context: context
        )

        [query, execute_query(query, client: client)]
      end

      # Executes the given query, providing some extra logging if an exception occurs.
      def execute_query(query, client:)
        # Log the query before starting to execute it, in case there's a lambda timeout, in which case
        # we won't get any other logged messages for the query.
        @logger.info "Starting to execute query #{fingerprint_for(query)} for client #{client.description}."

        query.result
      rescue => ex
        @logger.error <<~EOS
          Query #{query.operation_name}[1] for client #{client.description} failed with an exception[2].

          [1] #{full_description_of(query)}

          [2] #{ex.class}: #{ex.message}
        EOS

        raise ex
      end

      # Returns a string that describes the query as completely as we can.
      # Note that `query.sanitized_query_string` is quite complete, but can be nil in
      # certain situations (such as when the query string itself is invalid!); we include
      # the fingerprint to make sure that we at least have some identification information
      # about the query.
      def full_description_of(query)
        "#{fingerprint_for(query)} #{query.sanitized_query_string}"
      end

      def fingerprint_for(query)
        query.query_string ? query.fingerprint : "(no query string)"
      end

      def slo_result_for(query, duration)
        latency_slo = directives_from_query_operation(query)
          .dig(schema.element_names.eg_latency_slo, schema.element_names.ms)

        if latency_slo.nil?
          nil
        elsif duration <= latency_slo
          "good"
        else
          "bad"
        end
      end

      def directives_from_query_operation(query)
        query.selected_operation&.directives&.to_h do |dir|
          arguments = dir.arguments.to_h { |arg| [arg.name, arg.value] }
          [dir.name, arguments]
        end || {}
      end
    end
  end
end
