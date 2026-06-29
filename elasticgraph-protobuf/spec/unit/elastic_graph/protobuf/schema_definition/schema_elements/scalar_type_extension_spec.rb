# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/protobuf/schema_definition/schema_elements/scalar_type_extension"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      module SchemaElements
        RSpec.describe ScalarTypeExtension do
          let(:scalar_type_class) do
            ::Class.new do
              include ScalarTypeExtension

              attr_reader :name

              def initialize(name:)
                @name = name
              end
            end
          end

          it "returns an explicitly configured proto field type" do
            scalar = scalar_type_class.new(name: "CustomScalar")
            scalar.proto_field(type: "fixed64")

            expect(scalar.to_proto_field_type).to eq("fixed64")
          end

          it "raises when no proto field type is configured" do
            scalar = scalar_type_class.new(name: "CustomScalar")

            expect {
              scalar.to_proto_field_type
            }.to raise_error(Errors::SchemaError, a_string_including("Protobuf field type not configured for scalar type `CustomScalar`"))
          end
        end
      end
    end
  end
end
