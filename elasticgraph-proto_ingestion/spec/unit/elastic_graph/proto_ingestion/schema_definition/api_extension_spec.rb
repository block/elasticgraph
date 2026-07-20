# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/api_extension"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe APIExtension do
        it "uses the configured package name" do
          proto = define_proto_schema do |s|
            s.proto_schema_artifacts package_name: "proto.package.v1"

            s.object_type "Address" do |t|
              t.field "street", "String"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "address", "Address"
              t.index "widgets"
            end
          end

          expect(proto).to include("package proto.package.v1;")
          expect(proto_type_def_from(proto, "Widget")).to include(".proto.package.v1.Address address = 2;")
        end

        it "maps every built-in scalar to a proto field type" do
          field_types = []
          proto = define_proto_schema do |s|
            s.object_type "Widget" do |t|
              SchemaElements::ScalarTypeExtension::BUILT_IN_SCALAR_PROTO_TYPES_BY_NAME.each_key do |type_name|
                t.field type_name.downcase, type_name
              end
              field_types = t.graphql_fields_by_name.values.map { |field| field.type.name }
              t.index "widgets"
            end
          end

          expect(field_types).to match_array(SchemaElements::ScalarTypeExtension::BUILT_IN_SCALAR_PROTO_TYPES_BY_NAME.keys)
          SchemaElements::ScalarTypeExtension::BUILT_IN_SCALAR_PROTO_TYPES_BY_NAME.each.with_index(1) do |(type_name, proto_type), field_number|
            expect(proto).to include("#{proto_type} #{type_name.downcase} = #{field_number};")
          end
        end

        it "rejects invalid package names when they are configured" do
          invalid_package_names = [
            "",
            :symbol_package,
            "my-app.events",
            "myapp..events",
            "1myapp.events",
            "myapp.events.",
            ".elasticgraph.events"
          ]

          aggregate_failures do
            invalid_package_names.each do |package_name|
              expect {
                define_proto_schema do |s|
                  s.proto_schema_artifacts package_name: package_name
                end
              }.to raise_error(Errors::SchemaError, a_string_including("`package_name`"))
            end
          end
        end
      end
    end
  end
end
