# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/json_ingestion_state"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Extension module applied to `ElasticGraph::SchemaDefinition::State` to support JSON ingestion state.
      #
      # @private
      module StateExtension
        # @dynamic json_ingestion_state
        attr_reader :json_ingestion_state

        def self.extended(state)
          state.instance_variable_set(:@json_ingestion_state, JSONIngestionState.new(schema_def_state: state))
        end
      end
    end
  end
end
