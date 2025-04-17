# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/index_config_normalizer"
require "elastic_graph/datastore_core/index_definition/base"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  class DatastoreCore
    module IndexDefinition
      class Index < Support::MemoizableData.define(
        :name, :route_with, :default_sort_clauses, :current_sources, :fields_by_path,
        :env_index_config, :defined_clusters, :datastore_clients_by_name, :env_agnostic_settings
      )
        # `Data.define` provides all these methods:
        # @dynamic name, route_with, default_sort_clauses, current_sources, fields_by_path, env_index_config, env_agnostic_settings
        # @dynamic defined_clusters, datastore_clients_by_name, initialize,

        # `include IndexDefinition::Base` provides all these methods. Steep should be able to detect it
        # but can't for some reason so we have to declare them with `@dynamic`.
        # @dynamic flattened_env_setting_overrides, routing_value_for_prepared_record, has_custom_routing?, cluster_to_query
        # @dynamic clusters_to_index_into, all_accessible_cluster_names, ignored_values_for_routing, searches_could_hit_incomplete_docs?, max_result_window
        # @dynamic accessible_cluster_names_to_index_into, accessible_from_queries?, known_related_query_rollover_indices, list_counts_field_paths_for_source
        include IndexDefinition::Base

        def mappings_in_datastore(datastore_client)
          IndexConfigNormalizer.normalize_mappings(datastore_client.get_index(name)["mappings"] || {})
        end

        # `ignore_unavailable: true` is needed to prevent errors when we delete non-existing non-rollover indices
        def delete_from_datastore(datastore_client)
          datastore_client.delete_indices(name)
        end

        # Indicates if this is a rollover index definition.
        #
        # Use of this is considered a mild code smell.  When feasible, it's generally better to
        # implement a new polymorphic API on the IndexDefinition interface, rather
        # then branching on the value of this predicate.
        def rollover_index_template?
          false
        end

        def index_expression_for_search
          name
        end

        # Returns an index name to use for write operations.
        def index_name_for_writes(record, timestamp_field_path: nil)
          name
        end

        # A concrete index has no related indices (really only rollover indices do).
        def related_rollover_indices(datastore_client, only_if_exists: false)
          []
        end
      end
    end
  end
end
