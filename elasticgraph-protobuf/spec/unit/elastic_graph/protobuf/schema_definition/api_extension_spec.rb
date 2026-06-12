# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/protobuf/schema_definition/api_extension"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      RSpec.describe APIExtension, :proto_schema do
        it "emits the configured package name and maps built-in scalars to proto field types" do
          results = define_proto_schema do |s|
            s.proto_schema_artifacts package_name: "sales.v1"

            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "count", "Int"
              t.field "cost", "Float"
              t.field "active", "Boolean"
              t.field "created_at", "DateTime"
              t.field "size_bytes", "JsonSafeLong"
              t.index "widgets"
            end
          end

          expect(proto_schema_from(results)).to include(
            "package sales.v1;",
            "string id = 1;",
            "int32 count = 2;",
            "double cost = 3;",
            "bool active = 4;",
            "string created_at = 5;",
            "int64 size_bytes = 6;"
          )
        end

        it "requires `package_name` to be a non-empty String" do
          expect {
            define_proto_schema do |s|
              s.proto_schema_artifacts package_name: ""
            end
          }.to raise_error(Errors::SchemaError, a_string_including("`package_name` must be a non-empty String"))

          expect {
            define_proto_schema do |s|
              s.proto_schema_artifacts package_name: :symbol_package
            end
          }.to raise_error(Errors::SchemaError, a_string_including("`package_name` must be a non-empty String"))
        end
      end
    end
  end
end
