# Copyright 2024 - 2026 Block, Inc.
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
        private

        # Overrides the base `artifacts_from_schema_def` method to add warehouse artifacts.
        #
        # This method is called when computing the list of schema artifacts. It calls super
        # to get the base artifacts, then appends the warehouse artifact if any warehouse
        # tables are defined.
        #
        # @return [Array<ElasticGraph::SchemaDefinition::SchemaArtifact>] the list of schema artifacts
        def artifacts_from_schema_def
          base_artifacts = super
          results = schema_definition_results # : ElasticGraph::SchemaDefinition::Results & ResultsExtension
          warehouse_config = results.warehouse_config

          # Only add the artifact if there are warehouse tables defined.
          return base_artifacts if warehouse_config["tables"].empty?

          warehouse_artifact = new_yaml_artifact(
            DATA_WAREHOUSE_FILE,
            warehouse_config,
            extra_comment_lines: ["This file contains Data Warehouse configuration generated from the ElasticGraph schema."]
          )

          base_artifacts + [warehouse_artifact]
        end
      end
    end
  end
end
