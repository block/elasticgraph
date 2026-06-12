# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/protobuf/schema_definition/schema"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      # Extension module for {ElasticGraph::SchemaDefinition::Results} that adds proto schema generation support.
      module ResultsExtension
        # Returns the generated proto schema.
        #
        # @return [String] complete `proto3` schema file contents
        def proto_schema
          @proto_schema ||= protobuf_schema_generator.to_proto
        end

        # Returns proto field-number mappings suitable for artifact storage.
        #
        # @return [Hash]
        def proto_field_number_mappings
          # Ensure generation has occurred before reading mappings from the generator.
          _ = proto_schema
          protobuf_schema_generator.field_number_mappings_for_artifact
        end

        private

        # Returns the wrapped state narrowed to include this gem's `StateExtension`. Centralizes
        # the Steep cast that's needed because Steep can't see the `extend(StateExtension)` applied
        # at runtime in {APIExtension.extended}.
        def protobuf_state
          state # : ElasticGraph::SchemaDefinition::State & StateExtension
        end

        def protobuf_schema_generator
          @protobuf_schema_generator ||= begin
            state = protobuf_state

            # Force `all_types` to materialize before generating. That applies the `on_built_in_types`
            # callbacks (including the built-in scalar `proto_field` configuration registered by
            # `APIExtension.extended`) and registers lazily-built types (such as derived indexed types)
            # in the state the generator reads from.
            all_types

            Schema.new(
              state: state,
              package_name: state.proto_schema_package_name,
              proto_enums_by_graphql_enum: state.proto_enums_by_graphql_enum,
              proto_field_number_mappings: state.proto_field_number_mappings
            )
          end
        end
      end
    end
  end
end
