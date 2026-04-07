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
      # Extends indices with JSON-schema-specific event requirements.
      module IndexExtension
        # @private
        def rollover(frequency, timestamp_field_path_name)
          super

          schema_def_state.after_user_definition_complete do
            public_field_path(timestamp_field_path_name, explanation: "it is referenced as an index `rollover` field")
              .path_parts
              .each { |field| field.json_schema nullable: false }
          end
        end

        # @private
        def route_with(routing_field_path_name)
          super

          schema_def_state.after_user_definition_complete do
            routing_field_path = public_field_path(routing_field_path_name, explanation: "it is referenced as an index `route_with` field")

            routing_field_path.path_parts[0..-2].each { |field| field.json_schema nullable: false }
            routing_field_path.last_part.json_schema nullable: false, pattern: ElasticGraph::SchemaDefinition::Indexing::Index::HAS_NON_WHITE_SPACE_REGEX
          end
        end
      end
    end
  end
end
