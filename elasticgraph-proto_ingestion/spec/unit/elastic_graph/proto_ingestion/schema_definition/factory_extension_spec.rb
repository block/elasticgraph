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

        it "rejects colliding proto type names as soon as the second type is defined" do
          expect {
            define_proto_schema do |s|
              s.enum_type "package" do |t|
                t.value "ACTIVE"
              end

              s.object_type "package_" do |t|
                t.field "id", "ID"
                t.index "packages"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("both map to the same proto type name `package_`"))
        end

        it "detects proto type name collisions after enum configuration blocks run" do
          proto_status = ::Data.define(:enums).new(enums: [])

          expect {
            define_proto_schema do |s|
              s.enum_type "CurrentStatus" do |t|
                t.value "ACTIVE"
                t.external_proto_enum proto_status,
                  proto: "myapp.types.Status",
                  import: "myapp/types/status.proto"
              end

              s.enum_type "PreviousStatus" do |t|
                t.value "ACTIVE"
                t.external_proto_enum proto_status,
                  proto: "myapp.types.Status",
                  import: "myapp/types/status.proto"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Type names `CurrentStatus` and `PreviousStatus`",
            "same proto type name `myapp.types.Status`"
          ))
        end
      end
    end
  end
end
