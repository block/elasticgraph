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
        it "emits the configured package name" do
          proto = define_proto_schema do |s|
            s.proto_schema_artifacts package_name: "sales.v1"

            s.object_type "Widget" do |t|
              t.field "id", "ID"
              t.index "widgets"
            end
          end

          expect(proto).to include("package sales.v1;")
        end

        it "maps every built-in scalar to a proto field type" do
          built_in_scalar_options = FactoryExtension::BUILT_IN_SCALAR_PROTO_OPTIONS_BY_NAME
          field_types = []
          proto = define_proto_schema do |s|
            s.object_type "Widget" do |t|
              built_in_scalar_options.each_key do |type_name|
                t.field type_name.downcase, type_name
              end
              field_types = t.graphql_fields_by_name.values.map { |field| field.type.name }
              t.index "widgets"
            end
          end

          expect(field_types).to match_array(built_in_scalar_options.keys)
          expect(proto).to include('import "google/protobuf/timestamp.proto";')
          built_in_scalar_options.each.with_index(1) do |(type_name, options), field_number|
            field_name = Identifier.field_name(type_name.downcase)
            expect(proto).to include("#{options.fetch(:type)} #{field_name} = #{field_number};")
          end
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

        it "rejects invalid package names when they are configured" do
          expect {
            define_proto_schema do |s|
              s.proto_schema_artifacts package_name: "my-app.events"
            end
          }.to raise_error(Errors::SchemaError, a_string_including("`package_name`", "my-app.events"))
        end
      end
    end
  end
end
