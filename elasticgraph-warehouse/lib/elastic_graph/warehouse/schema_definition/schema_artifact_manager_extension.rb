# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Extension module for {ElasticGraph::SchemaDefinition::SchemaArtifactManager} that adds
      # warehouse artifact generation support.
      #
      # @private
      module SchemaArtifactManagerExtension
        # Adds warehouse artifact to the artifact list after initialization.
        #
        # This method is called automatically after the SchemaArtifactManager is initialized.
        # It checks if the schema has warehouse table definitions and adds the data_warehouse.yaml
        # artifact if any tables are defined.
        #
        # @return [void]
        def add_warehouse_artifact
          # Only add the artifact if the results support warehouse_config (i.e., have the extension)
          return unless schema_definition_results.respond_to?(:warehouse_config)

          warehouse_config = schema_definition_results.warehouse_config

          # Only add the artifact if there are warehouse tables defined.
          return if warehouse_config.empty?

          warehouse_artifact = ElasticGraph::SchemaDefinition::SchemaArtifact.new(
            ::File.join(@schema_artifacts_directory, ::ElasticGraph::Warehouse::DATA_WAREHOUSE_FILE),
            warehouse_config,
            ->(hash) { ::YAML.dump(hash) },
            # :nocov: -- Lambda for loading YAML; not executed in tests
            ->(string) { ::YAML.safe_load(string, permitted_classes: [Symbol]) },
            # :nocov:
            ["This file contains Data Warehouse configuration generated from the ElasticGraph schema."]
          )
          @artifacts = (@artifacts + [warehouse_artifact]).sort_by(&:file_name)
        end
      end
    end
  end
end
