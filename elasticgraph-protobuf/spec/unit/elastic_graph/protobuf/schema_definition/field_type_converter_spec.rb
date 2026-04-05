# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/protobuf/schema_definition/field_type_converter"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      RSpec.describe FieldTypeConverter do
        it "converts non-list field types that expose to_proto_field_type" do
          resolved_type = ::Object.new
          resolved_type.define_singleton_method(:to_proto_field_type) { "bytes" }

          type_ref = ::Object.new
          type_ref.define_singleton_method(:unwrap_non_null) { type_ref }
          type_ref.define_singleton_method(:list?) { false }
          type_ref.define_singleton_method(:resolved) { resolved_type }
          type_ref.define_singleton_method(:unwrapped_name) { "Binary" }

          expect(FieldTypeConverter.convert(type_ref)).to eq("bytes")
        end

        it "raises for list types" do
          type_ref = ::Object.new
          type_ref.define_singleton_method(:unwrap_non_null) { type_ref }
          type_ref.define_singleton_method(:list?) { true }

          expect {
            FieldTypeConverter.convert(type_ref)
          }.to raise_error(Errors::SchemaError, a_string_including("only supports non-list types"))
        end

        it "raises when the resolved type does not expose to_proto_field_type" do
          type_ref = ::Object.new
          type_ref.define_singleton_method(:unwrap_non_null) { type_ref }
          type_ref.define_singleton_method(:list?) { false }
          type_ref.define_singleton_method(:resolved) { nil }
          type_ref.define_singleton_method(:unwrapped_name) { "UnknownType" }

          expect {
            FieldTypeConverter.convert(type_ref)
          }.to raise_error(Errors::SchemaError, a_string_including("Type `UnknownType` cannot be converted to proto"))
        end
      end
    end
  end
end
