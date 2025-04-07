# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "runtime_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #scalar_types_by_name" do
      include_context "RuntimeMetadata support"

      it "dumps the coercion adapter" do
        metadata = scalar_type_metadata_for "BigInt" do |s|
          s.scalar_type "BigInt" do |t|
            t.mapping type: "long"
            t.json_schema type: "integer"
            t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
          end
        end

        expect(metadata).to eq scalar_type_with(coercion_adapter_ref: {
          "name" => "ExampleScalarCoercionAdapter",
          "require_path" => "support/example_extensions/scalar_coercion_adapter"
        })
      end

      it "dumps the indexing preparer" do
        metadata = scalar_type_metadata_for "BigInt" do |s|
          s.scalar_type "BigInt" do |t|
            t.mapping type: "long"
            t.json_schema type: "integer"
            t.prepare_for_indexing_with "ExampleIndexingPreparer", defined_at: "support/example_extensions/indexing_preparer"
          end
        end

        expect(metadata).to eq scalar_type_with(indexing_preparer_ref: {
          "name" => "ExampleIndexingPreparer",
          "require_path" => "support/example_extensions/indexing_preparer"
        })
      end

      it "verifies the validity of the extension when `coerce_with` is called" do
        define_schema do |s|
          s.scalar_type "BigInt" do |t|
            t.mapping type: "long"
            t.json_schema type: "integer"

            expect {
              t.coerce_with "NotAValidConstant", defined_at: "support/example_extensions/scalar_coercion_adapter"
            }.to raise_error NameError, a_string_including("NotAValidConstant")
          end
        end
      end

      it "verifies the validity of the extension when `indexing_preparer` is called" do
        define_schema do |s|
          s.scalar_type "BigInt" do |t|
            t.mapping type: "long"
            t.json_schema type: "integer"

            expect {
              t.prepare_for_indexing_with "NotAValidConstant", defined_at: "support/example_extensions/indexing_preparer"
            }.to raise_error NameError, a_string_including("NotAValidConstant")
          end
        end
      end

      it "dumps runtime metadata for the all scalar types (including ones described in the GraphQL spec) so that the indexing preparer is explicitly defined" do
        dumped_scalar_types = define_schema.runtime_metadata.scalar_types_by_name.keys

        expect(dumped_scalar_types).to include("ID", "Int", "Float", "String", "Boolean")
      end

      it "allows `on_built_in_types` to customize scalar runtime metadata" do
        metadata = scalar_type_metadata_for "Int" do |s|
          s.on_built_in_types do |t|
            if t.is_a?(SchemaElements::ScalarType)
              t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
            end
          end
        end

        expect(metadata.coercion_adapter_ref).to eq({
          "name" => "ExampleScalarCoercionAdapter",
          "require_path" => "support/example_extensions/scalar_coercion_adapter"
        })
      end

      def scalar_type_metadata_for(name, &block)
        define_schema(&block)
          .runtime_metadata
          .scalar_types_by_name
          .fetch(name)
      end
    end
  end
end
