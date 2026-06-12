# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      # Extension module applied to `ElasticGraph::SchemaDefinition::State` to hold protobuf configuration.
      #
      # @private
      module StateExtension
        # @dynamic proto_schema_package_name, proto_schema_package_name=
        # @dynamic proto_enums_by_graphql_enum, proto_enums_by_graphql_enum=
        # @dynamic proto_field_number_mappings, proto_field_number_mappings=
        attr_accessor :proto_schema_package_name, :proto_enums_by_graphql_enum, :proto_field_number_mappings

        def self.extended(state)
          state.proto_schema_package_name = "elasticgraph"
          state.proto_enums_by_graphql_enum = {}
          state.proto_field_number_mappings = {}
        end
      end
    end
  end
end
