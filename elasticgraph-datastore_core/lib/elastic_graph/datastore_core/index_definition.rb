# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/index_definition/index"
require "elastic_graph/datastore_core/index_definition/rollover_index_template"
require "elastic_graph/errors"

module ElasticGraph
  class DatastoreCore
    # Represents the definition of a datastore index (or rollover template).
    # Intended to be an entry point for working with datastore indices.
    #
    # This module contains common implementation logic for both the rollover and non-rollover
    # case, as well as a `with` factory method.
    module IndexDefinition
      def self.with(name:, runtime_metadata:, config:, datastore_clients_by_name:)
        if (env_index_config = config.index_definitions[name]).nil?
          raise Errors::ConfigError, "Configuration does not provide an index definition for `#{name}`, " \
            "but it is required so we can identify the datastore cluster(s) to query and index into."
        end

        common_args = {
          name: name,
          route_with: runtime_metadata.route_with,
          default_sort_clauses: runtime_metadata.default_sort_fields.map(&:to_query_clause),
          current_sources: runtime_metadata.current_sources,
          fields_by_path: runtime_metadata.fields_by_path,
          env_index_config: env_index_config,
          defined_clusters: config.clusters.keys.to_set,
          datastore_clients_by_name: datastore_clients_by_name
        }

        if (rollover = runtime_metadata.rollover)
          RolloverIndexTemplate.new(
            timestamp_field_path: rollover.timestamp_field_path,
            frequency: rollover.frequency,
            index_args: common_args,
            **common_args
          )
        else
          Index.new(**common_args)
        end
      end
    end
  end
end
