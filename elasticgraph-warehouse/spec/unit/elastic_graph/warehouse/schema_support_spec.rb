# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "support/warehouse_schema_support"

module ElasticGraph
  module Warehouse
    RSpec.describe SchemaSupport, :warehouse_schema do
      describe "#define_warehouse_schema" do
        it "defines a schema with warehouse extensions and snake_case form" do
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.object_type "TestType" do |t|
              t.field "id", "ID"
            end
          end

          expect(results).to be_a(ElasticGraph::SchemaDefinition::Results)
          expect(results.state.object_types_by_name).to have_key("TestType")

          # Verify the object type has warehouse extensions
          object_type = results.state.object_types_by_name["TestType"]
          expect(object_type).to be_a(SchemaDefinition::ObjectAndInterfaceExtension)
        end

        it "accepts additional options and passes them through" do
          # Test that additional options can be passed through without error
          results = define_warehouse_schema do |s|
            s.json_schema_version 1

            s.object_type "TestType" do |t|
              t.field "id", "ID"
            end
          end

          expect(results.state.object_types_by_name).to have_key("TestType")
        end
      end
    end
  end
end
