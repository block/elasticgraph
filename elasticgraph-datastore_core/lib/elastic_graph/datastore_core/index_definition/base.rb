# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/index_config_normalizer"
require "elastic_graph/errors"
require "elastic_graph/support/hash_util"

module ElasticGraph
  class DatastoreCore
    module IndexDefinition
      # This module contains common implementation logic for both the rollover and non-rollover
      # implementations of the common IndexDefinition type.
      module Base
        # Returns any setting overrides for this index from the environment-specific config file,
        # after flattening it so that it can be directly used in a create index request.
        def flattened_env_setting_overrides
          @flattened_env_setting_overrides ||= Support::HashUtil.flatten_and_stringify_keys(
            env_index_config.setting_overrides,
            prefix: "index"
          )
        end

        # Gets the routing value for the given `prepared_record`. Notably, `prepared_record` must be previously
        # prepared with an `Indexer::RecordPreparer` in order to ensure that it uses internal index
        # field names (to align with `route_with_path`/`route_with` which also use the internal name) rather
        # than the public field name (which can differ).
        def routing_value_for_prepared_record(prepared_record, route_with_path: route_with, id_path: "id")
          return nil unless has_custom_routing?

          unless route_with_path
            raise Errors::ConfigError, "`#{self}` uses custom routing, but `route_with_path` is misconfigured (was `nil`)"
          end

          config_routing_value = Support::HashUtil.fetch_value_at_path(prepared_record, route_with_path.split(".")).to_s
          return config_routing_value unless ignored_values_for_routing.include?(config_routing_value)

          Support::HashUtil.fetch_value_at_path(prepared_record, id_path.split(".")).to_s
        end

        def has_custom_routing?
          route_with != "id"
        end

        def max_result_window
          @max_result_window ||= flattened_env_setting_overrides.fetch("index.max_result_window") do
            env_agnostic_settings.fetch("index.max_result_window")
          end
        end

        # Indicates if a search on this index definition may hit incomplete documents. An incomplete document
        # can occur when multiple event types flow into the same index. An index that has only one source type
        # can never have incomplete documents, but an index that has 2 or more sources can have incomplete
        # documents when the "primary" event type hasn't yet been received for a document.
        #
        # This case is notable because we need to apply automatic filtering in order to hide documents that are
        # not yet complete.
        #
        # Note: determining this value sometimes requires that we query the datastore for the record of all
        # sources that an index has ever had. This value changes very, very rarely, and we don't want to slow
        # down every GraphQL query by adding the extra query against the datastore, so we cache the value here.
        def searches_could_hit_incomplete_docs?
          return @searches_could_hit_incomplete_docs if defined?(@searches_could_hit_incomplete_docs)

          if current_sources.size > 1
            # We know that incomplete docs are possible, without needing to check sources recorded in `_meta`.
            @searches_could_hit_incomplete_docs = true
          else
            # While our current configuration can't produce incomplete documents, some may already exist in the index
            # if we previously had some `sourced_from` fields (but no longer have them). Here we check for the sources
            # we've recorded in `_meta` to account for that.
            client = datastore_clients_by_name.fetch(cluster_to_query)
            recorded_sources = mappings_in_datastore(client).dig("_meta", "ElasticGraph", "sources") || []
            sources = recorded_sources.union(current_sources.to_a)

            @searches_could_hit_incomplete_docs = sources.size > 1
          end
        end

        def cluster_to_query
          env_index_config.query_cluster
        end

        def clusters_to_index_into
          env_index_config.index_into_clusters.tap do |clusters_to_index_into|
            raise Errors::ConfigError, "No `index_into_clusters` defined for #{self} in env_index_config" unless clusters_to_index_into
          end
        end

        def ignored_values_for_routing
          env_index_config.ignore_routing_values
        end

        # Returns a list of all defined datastore clusters this index resides within.
        def all_accessible_cluster_names
          @all_accessible_cluster_names ||=
            # Using `_` because steep doesn't understand that `compact` removes nils.
            (clusters_to_index_into + [_ = cluster_to_query]).compact.uniq.select do |name|
              defined_clusters.include?(name)
            end
        end

        def accessible_cluster_names_to_index_into
          @accessible_cluster_names_to_index_into ||= clusters_to_index_into.select do |name|
            defined_clusters.include?(name)
          end
        end

        # Indicates whether not the index is be accessible from GraphQL queries, by virtue of
        # the `cluster_to_query` being a defined cluster or not. This will be used to
        # hide GraphQL schema elements that can't be queried when our config omits the means
        # to query an index (e.g. due to lacking a configured URL).
        def accessible_from_queries?
          return false unless (cluster = cluster_to_query)
          defined_clusters.include?(cluster)
        end

        # Returns a list of indices related to this template in the datastore cluster this
        # index definition is configured to query. Note that for performance reasons, this method
        # memoizes the result of querying the datastore for its current list of indices, and as
        # a result the return value may be out of date. If it is absolutely essential that you get
        # an up-to-date list of related indices, use `related_rollover_indices(datastore_client`) instead of
        # this method.
        #
        # Note, however, that indices generally change *very* rarely (say, monthly or yearly) and as such
        # this will very rarely be out of date, even with the memoization.
        def known_related_query_rollover_indices
          @known_related_query_rollover_indices ||= cluster_to_query&.then do |name|
            # For query purposes, we only want indices that exist. If we return a query that is defined in our configuration
            # but does not exist, and that gets used in a search index expression (even for the purposes of excluding it!),
            # the datastore will return an error.
            related_rollover_indices(datastore_clients_by_name.fetch(name), only_if_exists: true)
          end || []
        end

        # Returns a set of all of the field paths to subfields of the special `LIST_COUNTS_FIELD`
        # that contains the element counts of all list fields. The returned set is filtered based
        # on the provided `source` to only contain the paths of fields that are populated by the
        # given source.
        def list_counts_field_paths_for_source(source)
          @list_counts_field_paths_for_source ||= {} # : ::Hash[::String, ::Set[::String]]
          @list_counts_field_paths_for_source[source] ||= identify_list_counts_field_paths_for_source(source)
        end

        def to_s
          "#<#{self.class.name} #{name}>"
        end
        alias_method :inspect, :to_s

        private

        def identify_list_counts_field_paths_for_source(source)
          fields_by_path.filter_map do |path, field|
            path if field.source == source && path.split(".").include?(LIST_COUNTS_FIELD)
          end.to_set
        end
      end
    end
  end
end
