# Copyright 2024 - 2026 Block, Inc.
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
      RSpec.describe EnumTypeExtension, :warehouse_schema do
        it "maps enum fields to STRING columns" do
          results = define_warehouse_schema do |s|
            s.enum_type "Status" do |t|
              t.value "ACTIVE"
              t.value "INACTIVE"
              t.value "PENDING"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          expect(warehouse_column_def_from(results, "accounts", "status")).to eq "status STRING"
        end
      end
    end
  end
end
