# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        # Extends indices with JSON-schema-specific event requirements.
        module IndexExtension
          # @private
          def require_id_in_json_schema
            schema_def_state.after_user_definition_complete do
              # @type var routing_field_path: _JSONFieldPath
              routing_field_path = _ = self.routing_field_path
              routing_field_path.last_part.json_schema nullable: false
            end
          end

          # @private
          def rollover(frequency, timestamp_field_path_name)
            super

            schema_def_state.after_user_definition_complete do
              # @type var timestamp_field_path: _JSONFieldPath
              timestamp_field_path = _ = public_field_path(timestamp_field_path_name, explanation: "it is referenced as an index `rollover` field")
              timestamp_field_path
                .path_parts
                .each { |field| field.json_schema nullable: false }
            end
          end

          # @private
          def route_with(routing_field_path_name)
            super

            schema_def_state.after_user_definition_complete do
              # @type var routing_field_path: _JSONFieldPath
              routing_field_path = _ = public_field_path(routing_field_path_name, explanation: "it is referenced as an index `route_with` field")

              routing_field_path.path_parts.take(routing_field_path.path_parts.size - 1).each { |field| field.json_schema nullable: false }
              routing_field_path.last_part.json_schema nullable: false, pattern: ElasticGraph::SchemaDefinition::Indexing::Index::HAS_NON_WHITE_SPACE_REGEX
            end
          end
        end
      end
    end
  end
end
