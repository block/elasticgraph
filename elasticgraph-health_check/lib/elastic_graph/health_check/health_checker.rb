# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/health_check/config"
require "elastic_graph/health_check/health_status"
require "elastic_graph/support/threading"
require "time"

module ElasticGraph
  module HealthCheck
    class HealthChecker
      # Static factory method that builds a HealthChecker from an ElasticGraph::GraphQL instance.
      def self.build_from(graphql)
        new(
          schema: graphql.schema,
          config: HealthCheck::Config.from_parsed_yaml(graphql.config.extension_settings),
          datastore_search_router: graphql.datastore_search_router,
          datastore_query_builder: graphql.datastore_query_builder,
          datastore_clients_by_name: graphql.datastore_core.clients_by_name,
          clock: graphql.clock,
          logger: graphql.logger
        )
      end

      def initialize(
        schema:,
        config:,
        datastore_search_router:,
        datastore_query_builder:,
        datastore_clients_by_name:,
        clock:,
        logger:
      )
        @schema = schema
        @datastore_search_router = datastore_search_router
        @datastore_query_builder = datastore_query_builder
        @datastore_clients_by_name = datastore_clients_by_name
        @clock = clock
        @logger = logger
        @indexed_document_types_by_name = @schema.indexed_document_types.to_h { |t| [t.name.to_s, t] }

        @config = validate_and_normalize_config(config)
      end

      def check_health
        recency_queries_by_type_name = @config.data_recency_checks.to_h do |type_name, recency_config|
          [type_name, build_recency_query_for(type_name, recency_config)]
        end

        recency_results_by_query, *cluster_healths = execute_in_parallel(
          lambda { @datastore_search_router.msearch(recency_queries_by_type_name.values) },
          *@config.clusters_to_consider.map do |cluster|
            lambda { [cluster, @datastore_clients_by_name.fetch(cluster).get_cluster_health] }
          end
        )

        HealthStatus.new(
          cluster_health_by_name: build_cluster_health_by_name(cluster_healths.to_h),
          latest_record_by_type: build_latest_record_by_type(recency_results_by_query, recency_queries_by_type_name)
        )
      end

      private

      def build_recency_query_for(type_name, recency_config)
        type = @indexed_document_types_by_name.fetch(type_name)

        @datastore_query_builder.new_query(
          search_index_definitions: type.search_index_definitions,
          filter: build_index_optimization_filter_for(recency_config),
          requested_fields: ["id", recency_config.timestamp_field],
          document_pagination: {first: 1},
          sort: [{recency_config.timestamp_field => {"order" => "desc"}}]
        )
      end

      # To make the recency query more optimal, we filter on the timestamp field. This can provide
      # a couple optimizations:
      #
      # - If its a rollover index and the timestamp is the field we use for rollover, this allows
      #   the ElasticGraph query engine to hit only a subset of indices for better perf.
      # - We've been told (by AWS support) that sorting a larger result set if more expensive than
      #   a small result set (presumably larger than filtering cost) so even if we can't limit what
      #   indices we hit with this, it should still be helpful.
      #
      # However, there's a bit of a risk of not actually finding the latest record if we include
      # this filter. What we have here is a compromise: we "lookback" up to 100 times the
      # `expected_max_recency_seconds`. For example, if that's set at 30, we'd search the last 3000
      # seconds of data, which should be plenty of lookback for most cases, while still allowing
      # a filter optimization. Once the latest record is more than 100 times older than our threshold
      # the exact age of it is less interesting, anyway.
      def build_index_optimization_filter_for(recency_config)
        lookback_timestamp = @clock.now - (recency_config.expected_max_recency_seconds * 100)
        {recency_config.timestamp_field => {"gte" => lookback_timestamp.iso8601}}
      end

      def execute_in_parallel(*lambdas)
        Support::Threading.parallel_map(lambdas) { |l| l.call }
      end

      def build_cluster_health_by_name(cluster_healths)
        cluster_healths.transform_values do |health|
          health_status_fields = DATASTORE_CLUSTER_HEALTH_FIELDS.to_h do |field_name|
            [field_name, health[field_name.to_s]]
          end

          HealthStatus::ClusterHealth.new(**health_status_fields)
        end
      end

      def build_latest_record_by_type(recency_results_by_query, recency_queries_by_type_name)
        recency_queries_by_type_name.to_h do |type_name, query|
          config = @config.data_recency_checks.fetch(type_name)

          latest_record = if (latest_doc = recency_results_by_query.fetch(query).first)
            timestamp = ::Time.iso8601(latest_doc.fetch(config.timestamp_field))

            HealthStatus::LatestRecord.new(
              id: latest_doc.id,
              timestamp: timestamp,
              seconds_newer_than_required: timestamp - (@clock.now - config.expected_max_recency_seconds)
            )
          end

          [type_name, latest_record]
        end
      end

      def validate_and_normalize_config(config)
        unrecognized_cluster_names = config.clusters_to_consider - all_known_clusters

        # @type var errors: ::Array[::String]
        errors = []

        if unrecognized_cluster_names.any?
          errors << "`health_check.clusters_to_consider` contains " \
            "unrecognized cluster names: #{unrecognized_cluster_names.join(", ")}"
        end

        # Here, we determine which of the specified `clusters_to_consider` are actually available for datastore health checks (green/yellow/red).
        # Before partitioning, we remove `unrecognized_cluster_names` as those will be reported through a separate error mechanism (above).
        #
        # Below, `available_clusters_to_consider` will replace `clusters_to_consider` in the returned `Config` instance.
        available_clusters_to_consider, unavailable_clusters_to_consider =
          (config.clusters_to_consider - unrecognized_cluster_names).partition { |it| @datastore_clients_by_name.key?(it) }

        if unavailable_clusters_to_consider.any?
          @logger.warn("#{unavailable_clusters_to_consider.length} cluster(s) were unavailable for health-checking: #{unavailable_clusters_to_consider.join(", ")}")
        end

        valid_type_names, invalid_type_names = config
          .data_recency_checks.keys
          .partition { |type| @indexed_document_types_by_name.key?(type) }

        if invalid_type_names.any?
          errors << "Some `health_check.data_recency_checks` types are not recognized indexed types: " \
            "#{invalid_type_names.join(", ")}"
        end

        # It is possible to configure a GraphQL endpoint that has a healthcheck set up on type A, but doesn't actually
        # have access to the datastore cluster that backs type A. In that case, we want to skip the health check - if the endpoint
        # can't access type A, its health (or unhealth) is immaterial.
        #
        # So below, filter to types that have all of their datastore clusters available for querying.
        available_type_names, unavailable_type_names = valid_type_names.partition do |type_name|
          @indexed_document_types_by_name.fetch(type_name).search_index_definitions.all? do |search_index_definition|
            @datastore_clients_by_name.key?(search_index_definition.cluster_to_query.to_s)
          end
        end

        if unavailable_type_names.any?
          @logger.warn("#{unavailable_type_names.length} type(s) were unavailable for health-checking: #{unavailable_type_names.join(", ")}")
        end

        # @type var invalid_timestamp_fields_by_type: ::Hash[::String, ::String]
        invalid_timestamp_fields_by_type = {}
        # @type var normalized_data_recency_checks: ::Hash[::String, Config::DataRecencyCheck]
        normalized_data_recency_checks = {}

        available_type_names.each do |type|
          check = config.data_recency_checks.fetch(type)
          field = @indexed_document_types_by_name
            .fetch(type)
            .fields_by_name[check.timestamp_field]

          if field&.type&.unwrap_fully&.name.to_s == "DateTime"
            # @type var field: GraphQL::Schema::Field
            # Convert the config so that we have a reference to the index field name.
            normalized_data_recency_checks[type] = check.with(timestamp_field: field.name_in_index.to_s)
          else
            invalid_timestamp_fields_by_type[type] = check.timestamp_field
          end
        end

        if invalid_timestamp_fields_by_type.any?
          errors << "Some `health_check.data_recency_checks` entries have invalid timestamp fields: " \
            "#{invalid_timestamp_fields_by_type.map { |k, v| "#{k} (#{v})" }.join(", ")}"
        end

        raise Errors::ConfigError, errors.join("\n\n") unless errors.empty?
        config.with(
          data_recency_checks: normalized_data_recency_checks,
          clusters_to_consider: available_clusters_to_consider
        )
      end

      def all_known_clusters
        @all_known_clusters ||= @indexed_document_types_by_name.flat_map do |_, index_type|
          index_type.search_index_definitions.flat_map do |it|
            [it.cluster_to_query] + it.clusters_to_index_into
          end
        end + @datastore_clients_by_name.keys
      end
    end
  end
end
