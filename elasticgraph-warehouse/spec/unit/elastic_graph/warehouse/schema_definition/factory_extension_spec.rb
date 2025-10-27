# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/api_extension"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      RSpec.describe FactoryExtension, :warehouse_schema do
        it "extends enum types with EnumTypeExtension when block is given" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.enum_type "Status" do |t|
              t.value "ACTIVE"
            end
          end

          enum_type = results.state.enum_types_by_name["Status"]
          expect(enum_type).to be_a(EnumTypeExtension)
        end

        it "extends interface types with ObjectAndInterfaceExtension when block is given" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.interface_type "Node" do |t|
              t.field "id", "ID"
            end
          end

          interface_type = results.state.types_by_name["Node"]
          expect(interface_type).to be_a(ObjectAndInterfaceExtension)
        end

        it "extends object types with ObjectAndInterfaceExtension when block is given" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.object_type "User" do |t|
              t.field "id", "ID"
            end
          end

          object_type = results.state.object_types_by_name["User"]
          expect(object_type).to be_a(ObjectAndInterfaceExtension)
        end

        it "extends object types with ObjectAndInterfaceExtension when no block is given" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.object_type "User"
          end

          object_type = results.state.object_types_by_name["User"]
          expect(object_type).to be_a(ObjectAndInterfaceExtension)
        end

        it "extends scalar types with ScalarTypeExtension when block is given" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.scalar_type "CustomScalar" do |t|
              t.mapping type: "keyword"
              t.json_schema type: "string"
              t.warehouse_column type: "STRING"
            end
          end

          scalar_type = results.state.scalar_types_by_name["CustomScalar"]
          expect(scalar_type).to be_a(ScalarTypeExtension)
        end
      end
    end
  end
end
