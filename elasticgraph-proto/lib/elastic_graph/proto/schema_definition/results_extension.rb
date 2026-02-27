# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto/schema_definition/schema"

module ElasticGraph
  module Proto
    module SchemaDefinition
      # Extension module for Results that adds proto schema generation support.
      module ResultsExtension
        # Returns the generated proto schema.
        #
        # @return [String] complete `proto3` schema file contents
        def proto_schema
          @proto_schema ||= proto_schema_generator.to_proto
        end

        # Returns proto field-number mappings suitable for artifact storage.
        #
        # @return [Hash]
        def proto_field_number_mappings
          # Ensure generation has occurred before reading mappings from the generator.
          _ = proto_schema
          proto_schema_generator.field_number_mappings_for_artifact
        end

        # @private
        def replace_json_schema_artifacts_with_proto?
          state.api.respond_to?(:replace_json_schema_artifacts_with_proto?) &&
            state.api.replace_json_schema_artifacts_with_proto?
        end

        private

        def proto_schema_generator
          @proto_schema_generator ||= build_proto_schema_generator
        end

        def build_proto_schema_generator
          package_name =
            if state.api.respond_to?(:proto_schema_package_name)
              state.api.proto_schema_package_name
            else
              "elasticgraph"
            end

          proto_enums_by_graphql_enum =
            if state.api.respond_to?(:proto_enums_by_graphql_enum)
              state.api.proto_enums_by_graphql_enum
            else
              {}
            end

          proto_field_number_mappings =
            if state.api.respond_to?(:proto_field_number_mappings)
              state.api.proto_field_number_mappings
            else
              {}
            end

          Schema.new(
            self,
            package_name: package_name,
            proto_enums_by_graphql_enum: proto_enums_by_graphql_enum,
            proto_field_number_mappings: proto_field_number_mappings
          )
        end
      end
    end
  end
end
