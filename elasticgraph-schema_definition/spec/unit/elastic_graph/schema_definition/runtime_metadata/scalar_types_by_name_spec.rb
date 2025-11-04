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
    float_types = ElasticGraph::SchemaDefinition::SchemaElements::ScalarType::FLOAT_TYPES
    string_types = ElasticGraph::SchemaDefinition::SchemaElements::ScalarType::STRING_TYPES
    integer_types = ElasticGraph::SchemaDefinition::SchemaElements::ScalarType::INTEGER_TYPES

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

      describe "`grouping_missing_value_placeholder`" do
        it "can be set to a number" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer") do |t|
            t.grouping_missing_value_placeholder(-1)
          end

          expect(grouping_missing_value_placeholder).to eq(-1)
        end

        it "can be set to a string" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("keyword", type: "string") do |t|
            t.grouping_missing_value_placeholder "missing"
          end

          expect(grouping_missing_value_placeholder).to eq("missing")
        end

        it "does not infer placeholder when placeholder is set to nil" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("keyword", type: "string")
          expect(grouping_missing_value_placeholder).not_to be_nil

          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("keyword", type: "string") do |t|
            t.grouping_missing_value_placeholder nil
          end
          expect(grouping_missing_value_placeholder).to be_nil
        end

        it "raises an error when placeholder is not a String, Numeric, or nil" do
          expect {
            grouping_missing_value_placeholder_for("keyword", type: "string") do |t|
              t.grouping_missing_value_placeholder :symbol
            end
          }.to raise_error Errors::SchemaError, a_string_including(
            "grouping_missing_value_placeholder must be a String or Numeric value",
            "got Symbol: :symbol"
          )
        end

        it "raises an error when placeholder is an array" do
          expect {
            grouping_missing_value_placeholder_for("keyword", type: "string") do |t|
              t.grouping_missing_value_placeholder ["invalid"]
            end
          }.to raise_error Errors::SchemaError, a_string_including(
            "grouping_missing_value_placeholder must be a String or Numeric value",
            "got Array: [\"invalid\"]"
          )
        end

        it "raises an error when placeholder is a hash" do
          expect {
            grouping_missing_value_placeholder_for("keyword", type: "string") do |t|
              t.grouping_missing_value_placeholder({key: "value"})
            end
          }.to raise_error Errors::SchemaError, a_string_including(
            "grouping_missing_value_placeholder must be a String or Numeric value",
            "got Hash"
          )
        end

        it "accepts integer values" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer") do |t|
            t.grouping_missing_value_placeholder 42
          end

          expect(grouping_missing_value_placeholder).to eq(42)
        end

        it "accepts float values" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("double", type: "number") do |t|
            t.grouping_missing_value_placeholder 3.14
          end

          expect(grouping_missing_value_placeholder).to eq(3.14)
        end

        float_types.each do |float_type|
          it "infers 'NaN' for float type #{float_type}" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for(float_type, type: "number")

            expect(grouping_missing_value_placeholder).to eq(MISSING_NUMERIC_PLACEHOLDER)
          end
        end

        string_types.each do |string_type|
          it "infers secure random string for string type #{string_type}" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for(string_type, type: "string")

            expect(grouping_missing_value_placeholder).to eq(MISSING_STRING_PLACEHOLDER)
          end
        end

        integer_types.grep_v(/long/).each do |int_type|
          it "does not infer placeholder for safe integer type #{int_type} with default coercion adapter" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for(int_type, type: "integer")

            expect(grouping_missing_value_placeholder).to be_nil
          end

          it "infers 'NaN' for safe integer type #{int_type} with custom coercion adapter" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for(int_type, type: "integer") do |t|
              t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
            end

            expect(grouping_missing_value_placeholder).to eq(MISSING_NUMERIC_PLACEHOLDER)
          end
        end

        it "does not infer placeholder for long types with JSON-safe min/max range and default coercion adapter" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer", minimum: JSON_SAFE_LONG_MIN, maximum: JSON_SAFE_LONG_MAX)

          expect(grouping_missing_value_placeholder).to be_nil
        end

        it "infers 'NaN' for long types with JSON-safe min/max range and custom coercion adapter" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer", minimum: JSON_SAFE_LONG_MIN, maximum: JSON_SAFE_LONG_MAX) do |t|
            t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
          end

          expect(grouping_missing_value_placeholder).to eq(MISSING_NUMERIC_PLACEHOLDER)
        end

        it "does not infer a value for long types with max too large" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer", minimum: -(2**53) + 1, maximum: (2**60) - 1) do |t|
            t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
          end

          expect(grouping_missing_value_placeholder).to be_nil
        end

        it "does not infer placeholder for long types with min too small" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer", minimum: -(2**60), maximum: (2**53) - 1) do |t|
            t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
          end

          expect(grouping_missing_value_placeholder).to be_nil
        end

        it "does not infer placeholder for long types with only minimum specified" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer", minimum: 0) do |t|
            t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
          end

          expect(grouping_missing_value_placeholder).to be_nil
        end

        it "does not infer placeholder for long types with only maximum specified" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer", maximum: 1000) do |t|
            t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
          end

          expect(grouping_missing_value_placeholder).to be_nil
        end

        it "does not infer placeholder for long types without min/max specified" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer") do |t|
            t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
          end

          expect(grouping_missing_value_placeholder).to be_nil
        end

        it "does not infer placeholder for unsigned_long types with safe maximum and default coercion adapter" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("unsigned_long", type: "integer", maximum: (2**53) - 1)

          expect(grouping_missing_value_placeholder).to be_nil
        end

        it "infers 'NaN' for unsigned_long types with safe maximum and custom coercion adapter" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("unsigned_long", type: "integer", maximum: (2**53) - 1) do |t|
            t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
          end

          expect(grouping_missing_value_placeholder).to eq(MISSING_NUMERIC_PLACEHOLDER)
        end

        it "does not infer placeholder for unsigned_long types with unsafe maximum" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("unsigned_long", type: "integer", maximum: (2**60) - 1) do |t|
            t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
          end

          expect(grouping_missing_value_placeholder).to be_nil
        end

        it "does not infer placeholder for unsigned_long types without maximum specified" do
          grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("unsigned_long", type: "integer") do |t|
            t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
          end

          expect(grouping_missing_value_placeholder).to be_nil
        end

        describe "boundary conditions for JSON-safe long ranges" do
          it "does not infer placeholder when exactly at safe boundaries with default coercion adapter" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer", minimum: JSON_SAFE_LONG_MIN, maximum: JSON_SAFE_LONG_MAX)

            expect(grouping_missing_value_placeholder).to be_nil
          end

          it "infers 'NaN' when exactly at safe boundaries with custom coercion adapter" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer", minimum: JSON_SAFE_LONG_MIN, maximum: JSON_SAFE_LONG_MAX) do |t|
              t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
            end

            expect(grouping_missing_value_placeholder).to eq(MISSING_NUMERIC_PLACEHOLDER)
          end

          it "does not infer placeholder when minimum is one below safe range" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer", minimum: JSON_SAFE_LONG_MIN - 1, maximum: JSON_SAFE_LONG_MAX) do |t|
              t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
            end

            expect(grouping_missing_value_placeholder).to be_nil
          end

          it "does not infer placeholder when maximum is one above safe range" do
            grouping_missing_value_placeholder = grouping_missing_value_placeholder_for("long", type: "integer", minimum: JSON_SAFE_LONG_MIN, maximum: JSON_SAFE_LONG_MAX + 1) do |t|
              t.coerce_with "ExampleScalarCoercionAdapter", defined_at: "support/example_extensions/scalar_coercion_adapter"
            end

            expect(grouping_missing_value_placeholder).to be_nil
          end
        end

        it "has expected value for all built-in scalar types" do
          results = define_schema
          built_in_scalars = results.state.scalar_types_by_name.keys
          scalar_types_by_name = results.runtime_metadata.scalar_types_by_name

          placeholders_by_scalar_type = built_in_scalars.to_h do |scalar_type|
            [scalar_type, scalar_types_by_name.fetch(scalar_type).grouping_missing_value_placeholder]
          end

          expect(placeholders_by_scalar_type).to eq({
            "Boolean" => nil,
            "Cursor" => MISSING_STRING_PLACEHOLDER,
            "Date" => nil,
            "DateTime" => nil,
            "Float" => MISSING_NUMERIC_PLACEHOLDER,
            "ID" => MISSING_STRING_PLACEHOLDER,
            "Int" => MISSING_NUMERIC_PLACEHOLDER, # GraphQL automatically coerces Int values
            "JsonSafeLong" => MISSING_NUMERIC_PLACEHOLDER, # custom coercion adapter coerces floats back to integers
            "LocalTime" => nil,
            "LongString" => nil, # outside of the JSON safe range.
            "String" => MISSING_STRING_PLACEHOLDER,
            "TimeZone" => MISSING_STRING_PLACEHOLDER,
            "Untyped" => MISSING_STRING_PLACEHOLDER
          })
        end

        def grouping_missing_value_placeholder_for(mapping_type, **json_schema)
          metadata = scalar_type_metadata_for "CustomScalar" do |s|
            s.scalar_type "CustomScalar" do |t|
              t.mapping type: mapping_type
              t.json_schema(**json_schema)
              yield t if block_given?
            end
          end

          metadata.grouping_missing_value_placeholder
        end
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
