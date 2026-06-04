# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        # Extends indices with JSON-schema-specific event requirements.
        module IndexExtension
          # @private
          def self.extended(index)
            index.schema_def_state.after_user_definition_complete do
              routing_field_path = index.routing_field_path # : ::ElasticGraph::SchemaDefinition::SchemaElements::FieldPath
              id_field = routing_field_path.last_part # : ::ElasticGraph::SchemaDefinition::SchemaElements::Field & SchemaElements::FieldExtension
              id_field.json_schema nullable: false
            end
          end

          # @private
          def rollover(frequency, timestamp_field_path_name)
            super

            schema_def_state.after_user_definition_complete do
              rollover_config = self.rollover_config # : ::ElasticGraph::SchemaDefinition::Indexing::RolloverConfig
              rollover_config
                .timestamp_field_path
                .path_parts
                .each do |field|
                  json_schema_field = field # : ::ElasticGraph::SchemaDefinition::SchemaElements::Field & SchemaElements::FieldExtension
                  json_schema_field.json_schema nullable: false
                end
            end
          end

          # @private
          def route_with(routing_field_path_name)
            super

            schema_def_state.after_user_definition_complete do
              routing_field_path = self.routing_field_path # : ::ElasticGraph::SchemaDefinition::SchemaElements::FieldPath

              routing_field_path
                .path_parts # : ::Array[::ElasticGraph::SchemaDefinition::SchemaElements::Field & SchemaElements::FieldExtension]
                .each { |field| field.json_schema nullable: false }

              routing_field = routing_field_path.last_part # : ::ElasticGraph::SchemaDefinition::SchemaElements::Field & SchemaElements::FieldExtension
              routing_field.json_schema pattern: HAS_NON_WHITE_SPACE_REGEX
            end
          end
        end
      end
    end
  end
end
