# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Carefully scoped monkey patches. These stitch the warehouse code into ElasticGraph when this gem is loaded.
# This file uses the same extension pattern as elasticgraph-apollo: extending instances via the Factory
# rather than monkey patching base classes directly.

require "elastic_graph/schema_definition/results"
require "elastic_graph/schema_definition/schema_artifact_manager"

# Load constants first
require_relative "constants"

# Load the implementation pieces we add
require_relative "warehouse_config/field_type/scalar"
require_relative "warehouse_config/field_type/object"
require_relative "warehouse_config/field_type/enum"
require_relative "warehouse_config/warehouse_table"

# Namespace for ElasticGraph library
module ElasticGraph
  # Namespace for warehouse-related functionality
  module Warehouse
    # Contains monkey patches that extend ElasticGraph core classes with warehouse functionality
    module Patches
      # Extends Results with warehouse_config support
      module Results
        # Returns the warehouse configuration generated from the schema definition
        #
        # @return [Hash<String, Hash>] a hash mapping table names to their configuration
        def warehouse_config
          @warehouse_config ||= generate_warehouse_config
        end

        private

        # Generates warehouse configuration from object types that have warehouse table definitions
        #
        # @return [Hash<String, Hash>] a hash mapping table names to their configuration
        def generate_warehouse_config
          tables = state.object_types_by_name.values
            .select { |t| t.respond_to?(:warehouse_table_def) }
            .filter_map(&:warehouse_table_def)
            .sort_by(&:name)
          tables.to_h { |i| [i.name, i.to_config] }
        end
      end

      # Extends SchemaArtifactManager to include data_warehouse.yaml artifact generation
      module SchemaArtifactManager
        # Initializes the SchemaArtifactManager and adds warehouse artifact if applicable
        #
        # @param schema_definition_results [ElasticGraph::SchemaDefinition::Results] the schema definition results
        # @param schema_artifacts_directory [String] directory where schema artifacts are stored
        # @param enforce_json_schema_version [Boolean] whether to enforce JSON schema version
        # @param output [IO, nil] output stream for warnings and messages
        # @param max_diff_lines [Integer] maximum number of diff lines to display
        # @return [void]
        def initialize(schema_definition_results:, schema_artifacts_directory:, enforce_json_schema_version:, output:, max_diff_lines: 50)
          super
          # Append the warehouse artifact to @artifacts after core initialization
          if schema_definition_results.respond_to?(:warehouse_config)
            begin
              warehouse_config = schema_definition_results.warehouse_config

              # Only add the artifact if there are warehouse tables defined
              unless warehouse_config.empty?
                warehouse_artifact = ElasticGraph::SchemaDefinition::SchemaArtifact.new(
                  ::File.join(schema_artifacts_directory, ::ElasticGraph::Warehouse::DATA_WAREHOUSE_FILE),
                  warehouse_config,
                  ->(hash) { ::YAML.dump(hash) },
                  # :nocov: -- Lambda for loading YAML; not executed in tests
                  ->(string) { ::YAML.safe_load(string, permitted_classes: [Symbol]) },
                  # :nocov:
                  ["This file contains Data Warehouse configuration generated from the ElasticGraph schema."]
                )
                @artifacts = (@artifacts + [warehouse_artifact]).sort_by(&:file_name)
              end
            rescue => e
              # Log warning if warehouse config generation fails, but don't fail the whole process
              output&.puts("WARNING: Failed to generate warehouse config: #{e.message}")
            end
          end
        end
      end
    end
  end
end

# Apply patches to Results and SchemaArtifactManager
# These use prepend because they need to wrap existing initialization logic
ElasticGraph::SchemaDefinition::Results.prepend(ElasticGraph::Warehouse::Patches::Results)
ElasticGraph::SchemaDefinition::SchemaArtifactManager.prepend(ElasticGraph::Warehouse::Patches::SchemaArtifactManager)
