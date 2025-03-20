# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "graphql_schema_spec_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "GraphQL schema generation", "#enum_type" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "can generate a simple enum type" do
          result = enum_type "Color" do |e|
            e.value "RED"
            e.value "GREEN"
            e.value "BLUE"
          end

          expect(result).to eq(<<~EOS)
            enum Color {
              RED
              GREEN
              BLUE
            }
          EOS
        end

        it "allows many values to be defined in one call for convenience (but value directives are not supported)" do
          result = enum_type "Color" do |e|
            # they can be individually listed
            e.values "RED", "GREEN"
            # ...or passed as a single array
            e.values %w[YELLOW ORANGE]
          end

          expect(result).to eq(<<~EOS)
            enum Color {
              RED
              GREEN
              YELLOW
              ORANGE
            }
          EOS
        end

        it "can generate directives on the type" do
          result = define_schema do |schema|
            schema.raw_sdl "directive @foo(size: Int = null) repeatable on ENUM"

            schema.enum_type "Color" do |e|
              e.directive "foo", size: 1
              e.directive "foo", size: 3
              e.value "RED"
              e.value "GREEN"
              e.value "BLUE"
            end
          end

          expect(type_def_from(result, "Color")).to eq(<<~EOS.strip)
            enum Color @foo(size: 1) @foo(size: 3) {
              RED
              GREEN
              BLUE
            }
          EOS
        end

        it "respects a configured type name override" do
          result = define_schema(type_name_overrides: {"Color" => "Hue"}) do |schema|
            schema.object_type "Widget" do |t|
              t.paginated_collection_field "hues", "Color"
            end

            schema.enum_type "Color" do |t|
              t.value "RED"
            end
          end

          expect(type_def_from(result, "Color")).to eq nil
          expect(type_def_from(result, "Hue")).to eq(<<~EOS.strip)
            enum Hue {
              RED
            }
          EOS

          expect(type_def_from(result, "HueInput")).to eq(<<~EOS.strip)
            enum HueInput {
              RED
            }
          EOS

          expect(type_def_from(result, "HueFilterInput")).not_to eq nil
          expect(type_def_from(result, "HueConnection")).not_to eq nil
          expect(type_def_from(result, "HueEdge")).not_to eq nil

          # Verify that there are _no_ `Color` types defined
          expect(result.lines.grep(/Color/)).to be_empty
        end

        it "respects a configured enum value override" do
          result = define_schema(enum_value_overrides_by_type: {Color: {RED: "PINK"}}) do |schema|
            schema.enum_type "Color" do |t|
              t.value "RED"
            end
          end

          expect(type_def_from(result, "Color")).to eq(<<~EOS.strip)
            enum Color {
              PINK
            }
          EOS
        end

        it "allows the input variant to be renamed to the same name as the output variant via a type name override" do
          result = define_schema(type_name_overrides: {"ColorInput" => "Color"}) do |schema|
            schema.object_type "Widget" do |t|
              t.paginated_collection_field "colors", "Color"
            end

            schema.enum_type "Color" do |t|
              t.value "RED"
            end
          end

          expect(type_def_from(result, "Color")).to eq(<<~EOS.strip)
            enum Color {
              RED
            }
          EOS

          expect(type_def_from(result, "ColorInput")).to eq nil

          # Verify that `ColorInput` isn't referenced anywhere in the schema.
          expect(result.lines.grep(/ColorInput/)).to be_empty
        end

        it "allows the input variant to be customized using `customize_derived_types`" do
          result = define_schema do |schema|
            schema.enum_type "Color" do |t|
              t.value "RED"

              t.customize_derived_types "ColorInput" do |dt|
                dt.directive "deprecated"
              end
            end
          end

          expect(type_def_from(result, "Color")).to eq(<<~EOS.strip)
            enum Color {
              RED
            }
          EOS

          expect(type_def_from(result, "ColorInput")).to eq(<<~EOS.strip)
            enum ColorInput @deprecated {
              RED
            }
          EOS
        end

        it "can generate directives on the values" do
          result = define_schema do |schema|
            schema.raw_sdl "directive @foo(size: Int = null) repeatable on ENUM_VALUE"

            schema.enum_type "Color" do |e|
              e.value "RED" do |v|
                v.directive "foo", size: 1
                v.directive "foo", size: 3
              end
              e.value "GREEN" do |v|
                v.directive "foo", size: 5
              end
              e.value "BLUE"
            end
          end

          expect(type_def_from(result, "Color")).to eq(<<~EOS.strip)
            enum Color {
              RED @foo(size: 1) @foo(size: 3)
              GREEN @foo(size: 5)
              BLUE
            }
          EOS
        end

        it "supports doc comments on the enum type and enum values" do
          result = enum_type "Color" do |e|
            e.documentation "The set of valid colors."
            e.value "RED" do |v|
              v.documentation "The color red."
            end
            e.value "GREEN" do |v|
              v.documentation <<~EOS
                The color green.
                (This is multiline.)
              EOS
            end
            e.value "BLUE"
          end

          expect(result).to eq(<<~EOS)
            """
            The set of valid colors.
            """
            enum Color {
              """
              The color red.
              """
              RED
              """
              The color green.
              (This is multiline.)
              """
              GREEN
              BLUE
            }
          EOS
        end

        it "raises a clear error when the enum type name is not formatted correctly" do
          expect {
            define_schema do |api|
              api.enum_type("Invalid.Name") {}
            end
          }.to raise_invalid_graphql_name_error_for("Invalid.Name")
        end

        it "raises a clear error when an enum value name is not formatted correctly" do
          expect {
            define_schema do |api|
              api.enum_type "Color" do |e|
                e.value "INVALID.NAME"
              end
            end
          }.to raise_invalid_graphql_name_error_for("INVALID.NAME")
        end

        it "raises a clear error when the type name has the type wrapping characters" do
          expect {
            define_schema do |api|
              api.enum_type "[InvalidName!]!" do |e|
                e.value "INVALID"
              end
            end
          }.to raise_invalid_graphql_name_error_for("[InvalidName!]!")
        end

        it "raises a clear error when the same type is defined multiple times" do
          expect {
            define_schema do |api|
              api.enum_type "Color" do |e|
                e.value "RED"
                e.value "GREEN"
                e.value "BLUE"
              end

              api.enum_type "Color" do |e|
                e.value "RED2"
                e.value "GREEN2"
                e.value "BLUE2"
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("Duplicate", "Color")
        end

        it "raises a clear error when the same value is defined multiple times" do
          expect {
            enum_type "Color" do |e|
              e.value "RED"
              e.value "GREEN"
              e.value "RED"
            end
          }.to raise_error Errors::SchemaError, a_string_including("Duplicate", "Color", "RED")
        end

        it "raises a clear error when no enum values are defined" do
          expect {
            enum_type "Color" do |e|
            end
          }.to raise_error Errors::SchemaError, a_string_including("Color", "has no values")
        end

        it "raises a clear error when values are defined with spaces in them" do
          expect {
            enum_type "Color" do |e|
              # Notice this uses `%[ ]`, not `%w[ ]`, which makes it a string, and not an array--woops.
              # It therefore has unintended whitespace and is invalid.
              e.values %(RED GREEN)
            end
          }.to raise_invalid_graphql_name_error_for("RED GREEN")
        end

        def enum_type(name, *args, **options, &block)
          result = define_schema do |api|
            api.enum_type(name, *args, **options, &block)
          end

          # We add a line break to match the expectations which use heredocs.
          type_def_from(result, name, include_docs: true) + "\n"
        end
      end
    end
  end
end
