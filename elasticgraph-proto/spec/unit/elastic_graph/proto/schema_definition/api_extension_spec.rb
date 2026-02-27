# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto/schema_definition/api_extension"

module ElasticGraph
  module Proto
    module SchemaDefinition
      RSpec.describe APIExtension do
        def build_api(built_in_types: [])
          factory = ::Object.new

          api = ::Object.new
          api.define_singleton_method(:factory) { factory }
          api.define_singleton_method(:on_built_in_types) do |&block|
            built_in_types.each(&block)
          end

          api.extend(APIExtension)
          [api, factory]
        end

        it "extends the factory, applies default artifact settings, and maps built-in scalars" do
          scalar_type = ::Struct.new(:name) do
            include ScalarTypeExtension
          end.new("String")

          api, factory = build_api(built_in_types: [scalar_type, ::Object.new])

          expect(factory).to be_a(FactoryExtension)
          expect(scalar_type.to_proto_field_type).to eq("string")
          expect(api.proto_schema_package_name).to eq("elasticgraph")
          expect(api.replace_json_schema_artifacts_with_proto?).to eq(false)
          expect(api.enforce_proto_field_number_mappings?).to eq(false)
        end

        it "stores proto artifact settings and mappings" do
          api, = build_api

          api.proto_schema_artifacts(
            package_name: "sales.v1",
            replace_json_schemas: true,
            field_number_mapping_file: "proto_field_numbers.yaml",
            enforce_field_number_mapping: true
          )
          api.proto_enum_mappings("Status" => {::Object => {}})
          api.configure_proto_field_number_mappings({"messages" => {"Account" => {"id" => 1}}}, enforce: true)

          expect(api.proto_schema_package_name).to eq("sales.v1")
          expect(api.replace_json_schema_artifacts_with_proto?).to eq(true)
          expect(api.proto_field_number_mapping_file).to eq("proto_field_numbers.yaml")
          expect(api.proto_enums_by_graphql_enum).to eq("Status" => {::Object => {}})
          expect(api.proto_field_number_mappings).to eq("messages" => {"Account" => {"id" => 1}})
          expect(api.enforce_proto_field_number_mappings?).to eq(true)
        end

        it "validates proto_schema_artifacts arguments" do
          api, = build_api

          expect {
            api.proto_schema_artifacts(replace_json_schemas: :yes)
          }.to raise_error(Errors::SchemaError, a_string_including("`replace_json_schemas` must be true or false"))

          expect {
            api.proto_schema_artifacts(enforce_field_number_mapping: :yes)
          }.to raise_error(Errors::SchemaError, a_string_including("`enforce_field_number_mapping` must be true or false"))

          expect {
            api.proto_schema_artifacts(field_number_mapping_file: 123)
          }.to raise_error(Errors::SchemaError, a_string_including("`field_number_mapping_file` must be a String"))

          expect {
            api.proto_schema_artifacts(enforce_field_number_mapping: true)
          }.to raise_error(Errors::SchemaError, a_string_including("Cannot enforce proto field-number mappings"))
        end

        it "validates configure_proto_field_number_mappings arguments" do
          api, = build_api

          expect {
            api.configure_proto_field_number_mappings({}, enforce: :yes)
          }.to raise_error(Errors::SchemaError, a_string_including("`enforce` must be true or false"))
        end
      end
    end
  end
end
