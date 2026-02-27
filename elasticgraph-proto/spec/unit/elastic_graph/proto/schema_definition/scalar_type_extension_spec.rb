# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto/schema_definition/scalar_type_extension"

module ElasticGraph
  module Proto
    module SchemaDefinition
      RSpec.describe ScalarTypeExtension do
        let(:scalar_type_class) do
          ::Class.new do
            include ScalarTypeExtension

            attr_reader :name

            def initialize(name:, json_schema_options:)
              @name = name
              @json_schema_options = json_schema_options
            end

            def json_schema_options
              @json_schema_options
            end
          end
        end

        it "returns an explicitly configured proto field type" do
          scalar = scalar_type_class.new(name: "CustomScalar", json_schema_options: {})
          scalar.proto_field(type: "fixed64")

          expect(scalar.to_proto_field_type).to eq("fixed64")
        end

        it "infers the proto field type from a string json_schema type" do
          scalar = scalar_type_class.new(name: "EmailAddress", json_schema_options: {type: "string"})

          expect(scalar.to_proto_field_type).to eq("string")
        end

        it "infers the proto field type from a symbol json_schema type" do
          scalar = scalar_type_class.new(name: "Count", json_schema_options: {type: :integer})

          expect(scalar.to_proto_field_type).to eq("int64")
        end

        it "infers the proto field type from an array json_schema type with null" do
          scalar = scalar_type_class.new(name: "MaybeFloat", json_schema_options: {type: [:null, :number, 7]})

          expect(scalar.to_proto_field_type).to eq("double")
        end

        it "raises when json_schema type cannot be inferred" do
          scalar = scalar_type_class.new(name: "Ambiguous", json_schema_options: {type: ["string", "integer"]})

          expect {
            scalar.to_proto_field_type
          }.to raise_error(Errors::SchemaError, a_string_including("Proto field type not configured for scalar type `Ambiguous`"))
        end

        it "raises when json_schema type is not a string, symbol, or array" do
          scalar = scalar_type_class.new(name: "Unknown", json_schema_options: {type: 123})

          expect {
            scalar.to_proto_field_type
          }.to raise_error(Errors::SchemaError, a_string_including("Proto field type not configured for scalar type `Unknown`"))
        end

        it "raises when no json_schema_options are exposed" do
          scalar = ::Class.new do
            include ScalarTypeExtension

            def name
              "WithoutJsonSchema"
            end
          end.new

          expect {
            scalar.to_proto_field_type
          }.to raise_error(Errors::SchemaError, a_string_including("Proto field type not configured for scalar type `WithoutJsonSchema`"))
        end
      end
    end
  end
end
