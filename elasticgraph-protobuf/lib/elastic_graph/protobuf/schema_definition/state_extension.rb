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
        # @dynamic proto_external_types, proto_external_types=
        # @dynamic proto_field_number_mappings, proto_field_number_mappings=
        # @dynamic proto_schema_syntax, proto_schema_syntax=
        # @dynamic proto_schema_headers, proto_schema_headers=
        attr_accessor :proto_schema_package_name, :proto_enums_by_graphql_enum, :proto_external_types,
          :proto_field_number_mappings, :proto_schema_syntax, :proto_schema_headers

        def self.extended(state)
          state.proto_schema_package_name = "elasticgraph"
          state.proto_enums_by_graphql_enum = {}
          state.proto_external_types = {}
          state.proto_field_number_mappings = {}
          state.proto_schema_syntax = :proto3
          state.proto_schema_headers = []
        end
      end
    end
  end
end
