# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/factory_extension"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe FactoryExtension do
        it "supports public type definitions without configuration blocks" do
          proto = define_proto_schema do |s|
            s.enum_type "Status"
            s.state.enum_types_by_name.fetch("Status").value "ACTIVE"
            s.state.factory.new_enum_value("STANDALONE", "STANDALONE")

            s.interface_type "Named"
            s.state.object_types_by_name.fetch("Named").field "name", "String"

            s.object_type "UnconfiguredRecord"
            s.state.object_types_by_name.fetch("UnconfiguredRecord").field "id", "ID"

            s.union_type "Entity"
            s.state.object_types_by_name.fetch("Entity").subtype "UnconfiguredRecord"
          end

          expect(proto).to eq("")
        end

        it "validates scalar type definitions without configuration blocks" do
          expect {
            define_proto_schema do |s|
              s.scalar_type "UnconfiguredScalar"
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Protobuf type not configured for scalar type `UnconfiguredScalar`"
          ))
        end
      end
    end
  end
end
