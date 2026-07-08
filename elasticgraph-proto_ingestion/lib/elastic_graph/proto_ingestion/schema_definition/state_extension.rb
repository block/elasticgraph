# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/proto_ingestion_state"

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
          state.instance_variable_set(
            :@proto_ingestion_state,
            ProtoIngestionState.new(
              package_name: "elasticgraph",
              field_number_mappings: {},
              syntax: :proto3,
              headers: []
            )
          )
        end
      end
    end
  end
end
