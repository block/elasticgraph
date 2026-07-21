# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion"
require "elastic_graph/proto_ingestion/schema_definition/proto_ingestion_state"
require "yaml"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Extension module applied to `ElasticGraph::SchemaDefinition::State` to hold protobuf configuration.
      #
      # @private
      module StateExtension
        # @dynamic proto_ingestion_state
        attr_reader :proto_ingestion_state

        def self.extended(state)
          field_number_mappings =
            if (path = state.proto_field_numbers_path) && ::File.exist?(path)
              ::YAML.safe_load_file(path, aliases: false)
            else
              {} # : ::Hash[::String, untyped]
            end

          state.instance_variable_set(
            :@proto_ingestion_state,
            ProtoIngestionState.new(package_name: "elasticgraph", field_number_mappings: field_number_mappings)
          )
        end

        def proto_field_numbers_path
          return unless (path = path_to_schema)

          # The `./` prefix is dropped so that a schema definition at the root yields a path that
          # reads like the other artifact paths when the rake tasks report on it.
          ::File.join(::File.dirname(path), PROTO_FIELD_NUMBERS_FILE).delete_prefix("./")
        end
      end
    end
  end
end
