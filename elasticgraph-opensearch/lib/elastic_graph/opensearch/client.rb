# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/support/faraday_middleware/msearch_using_get_instead_of_post"
require "elastic_graph/support/faraday_middleware/support_timeouts"
require "elastic_graph/support/hash_util"
require "faraday"
require "faraday/retry"
require "opensearch"

module ElasticGraph
  # @private
  module OpenSearch
    # @private
    class Client
      # @dynamic cluster_name
      attr_reader :cluster_name

      def initialize(cluster_name, url:, faraday_adapter: nil, retry_on_failure: 3, logger: nil)
        @cluster_name = cluster_name

        @raw_client = ::OpenSearch::Client.new(
          adapter: faraday_adapter,
          url: url,
          retry_on_failure: retry_on_failure,
          # We use `logger` for both the tracer and logger to log everything we can. While the trace and log output do overlap, one is
          # not a strict superset of the other (for example, warnings go to `logger`, while full request bodies go to `tracer`).
          logger: logger,
          tracer: logger
        ) do |faraday|
          faraday.use Support::FaradayMiddleware::MSearchUsingGetInsteadOfPost
          faraday.use Support::FaradayMiddleware::SupportTimeouts

          # Note: this overrides the default retry exceptions, which includes `Faraday::TimeoutError`.
          # That's important because we do NOT want a retry on timeout -- a timeout indicates a slow,
          # expensive query, and is transformed to a `Errors::RequestExceededDeadlineError` by `SupportTimeouts`,
          # anyway.
          #
          # In addition, it's worth noting that the retry middleware ONLY retries known idempotent HTTP
          # methods (e.g. get/put/delete/head/options). POST requests will not be retried. We could
          # configure it to make it retry POSTs but we'd need to do an analysis of all ElasticGraph requests to
          # make sure all POST requests are truly idempotent, and at least for now, it's sufficient to skip
          # any POST requests we make.
          faraday.request :retry,
            exceptions: [::Faraday::ConnectionFailed, ::Faraday::RetriableResponse],
            max: retry_on_failure,
            retry_statuses: [500, 502, 503] # Internal Server Error, Bad Gateway, Service Unavailable

          yield faraday if block_given?
        end

        # Here we call `app` on each Faraday connection as a way to force it to resolve
        # all configured middlewares and adapters. If it cannot load a required dependency
        # (e.g. `httpx`), it'll fail fast with a clear error.
        #
        # Without this, we would instead get an error when the client was used to make
        # a request for the first time, which isn't as ideal.
        @raw_client.transport.transport.connections.each { |c| c.connection.app }
      end

      # Cluster APIs

      def get_cluster_health
        transform_errors { |c| c.cluster.health }
      end

      def get_node_os_stats
        transform_errors { |c| c.nodes.stats(metric: "os") }
      end

      def get_flat_cluster_settings
        transform_errors { |c| c.cluster.get_settings(flat_settings: true) }
      end

      # We only support persistent settings here because the Elasticsearch docs recommend against using transient settings:
      # https://www.elastic.co/guide/en/elasticsearch/reference/8.13/cluster-update-settings.html
      #
      # > We no longer recommend using transient cluster settings. Use persistent cluster settings instead. If a cluster becomes unstable,
      # > transient settings can clear unexpectedly, resulting in a potentially undesired cluster configuration.
      #
      # The OpenSearch documentation doesn't specifically mention this, but the same principle applies.
      def put_persistent_cluster_settings(settings)
        transform_errors { |c| c.cluster.put_settings(body: {persistent: settings}) }
      end

      # Script APIs

      # Gets the script with the given ID. Returns `nil` if the script does not exist.
      def get_script(id:)
        transform_errors { |c| c.get_script(id: id) }
      rescue ::OpenSearch::Transport::Transport::Errors::NotFound
        nil
      end

      def put_script(id:, body:, context:)
        transform_errors { |c| c.put_script(id: id, body: body, context: context) }
      end

      def delete_script(id:)
        transform_errors { |c| c.delete_script(id: id) }
      rescue ::OpenSearch::Transport::Transport::Errors::NotFound
        # it's ok if it's already not there.
      end

      # Index Template APIs

      def get_index_template(index_template_name)
        transform_errors do |client|
          client.indices.get_index_template(name: index_template_name)
            .fetch("index_templates").to_h do |entry|
              index_template = entry.fetch("index_template")

              # OpenSearch ignores  `flat_settings` on the `/_index_template` API (but _only_ returns flattened settings from the index
              # API). Here we flatten the settings to align with the flattened form ElasticGraph expects and uses everywhere.
              flattened_settings = Support::HashUtil.flatten_and_stringify_keys(index_template.fetch("template").fetch("settings"))

              index_template = index_template.merge({
                "template" => index_template.fetch("template").merge({
                  "settings" => flattened_settings
                })
              })

              [entry.fetch("name"), index_template]
            end.dig(index_template_name) || {}
        end
      rescue ::OpenSearch::Transport::Transport::Errors::NotFound
        {}
      end

      def put_index_template(name:, body:)
        transform_errors { |c| c.indices.put_index_template(name: name, body: body) }
      end

      def delete_index_template(index_template_name)
        transform_errors { |c| c.indices.delete_index_template(name: [index_template_name], ignore: [404]) }
      end

      # Index APIs

      def get_index(index_name)
        transform_errors do |client|
          client.indices.get(
            index: index_name,
            ignore_unavailable: true,
            flat_settings: true
          )[index_name] || {}
        end
      end

      def list_indices_matching(index_expression)
        transform_errors do |client|
          client
            .cat
            .indices(index: index_expression, format: "json", h: ["index"])
            .map { |index_hash| index_hash.fetch("index") }
        end
      end

      def create_index(index:, body:)
        transform_errors { |c| c.indices.create(index: index, body: body) }
      end

      def put_index_mapping(index:, body:)
        transform_errors { |c| c.indices.put_mapping(index: index, body: body) }
      end

      def put_index_settings(index:, body:)
        transform_errors { |c| c.indices.put_settings(index: index, body: body) }
      end

      def delete_indices(*index_names)
        # `allow_no_indices: true` is needed when we attempt to delete a non-existing index to avoid errors. For rollover indices,
        # when we delete the actual indices, we will always perform a wildcard deletion, and `allow_no_indices: true` is needed.
        #
        # Note that the Elasticsearch API documentation[^1] says that `allow_no_indices` defaults to `true` but a Elasticsearch Ruby
        # client code comment[^2] says it defaults to `false`. Regardless, we don't want to rely on the default behavior that could change.
        #
        # [^1]: https://www.elastic.co/guide/en/elasticsearch/reference/8.12/indices-delete-index.html#delete-index-api-query-params
        # [^2]: https://github.com/elastic/elasticsearch-ruby/blob/8.12/elasticsearch-api/lib/elasticsearch/api/actions/indices/delete.rb#L31
        transform_errors do |client|
          client.indices.delete(index: index_names, ignore_unavailable: true, allow_no_indices: true)
        end
      end

      # Document APIs

      def msearch(body:, headers: nil)
        transform_errors { |c| c.msearch(body: body, headers: headers) }
      end

      def bulk(body:, refresh: false)
        transform_errors { |c| c.bulk(body: body, filter_path: DATASTORE_BULK_FILTER_PATH, refresh: refresh) }
      end

      # Synchronously deletes all documents in the cluster. Intended for tests to give ourselves a clean slate.
      # Supports an `index` argument so the caller can limit the deletion to a specific "scope" (e.g. a set of indices with a common prefix).
      #
      # Overrides `scroll` to `10s` to avoid getting a "Trying to create too many scroll contexts" error, as discussed here:
      # https://discuss.elastic.co/t/too-many-scroll-contexts-with-update-by-query-and-or-delete-by-query/282325/1
      def delete_all_documents(index: "_all")
        transform_errors { |c| c.delete_by_query(index: index, body: {query: {match_all: _ = {}}}, refresh: true, scroll: "10s") }
      end

      private

      def transform_errors
        yield @raw_client
      rescue ::OpenSearch::Transport::Transport::Errors::BadRequest => ex
        raise Errors::BadDatastoreRequest, ex.message
      end
    end
  end
end
