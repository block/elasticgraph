# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"
require "elastic_graph/schema_definition/api"
require "elastic_graph/spec_support/schema_definition_helpers"
require "graphql"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      RSpec.describe TypeReference do
        let(:type_name_overrides) do
          {
            "RingAggregatedValues" => "RingValuesAggregated",
            "RingSortOrder" => "RingOrderSort",
            "RingSortOrderInput" => "RingOrderSortInput"
          }
        end

        let(:state) do
          schema_elements = SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: "snake_case")
          API.new(schema_elements, true, type_name_overrides: type_name_overrides).state
        end

        describe "#unwrap_list" do
          it "unwraps a type that has an outer list wrapping" do
            type = type_ref("[Int]")

            expect(type.unwrap_list.name).to eq "Int"
          end

          it "unwraps both non-null and list when a type has both" do
            type = type_ref("[Int]!")

            expect(type.unwrap_list.name).to eq "Int"
          end

          it "only unwraps a single list wrapping" do
            type = type_ref("[[Int]]")

            expect(type.unwrap_list.name).to eq "[Int]"
          end

          it "leaves an inner non-nullability intact" do
            type = type_ref("[Int!]")

            expect(type.unwrap_list.name).to eq "Int!"
          end
        end

        describe "#fully_unwrapped" do
          it "removes all wrappings no matter how many there are" do
            expect(type_ref("Int").fully_unwrapped.name).to eq "Int"
            expect(type_ref("Int!").fully_unwrapped.name).to eq "Int"
            expect(type_ref("[Int]").fully_unwrapped.name).to eq "Int"
            expect(type_ref("[Int!]").fully_unwrapped.name).to eq "Int"
            expect(type_ref("[Int!]!").fully_unwrapped.name).to eq "Int"
            expect(type_ref("[[Int!]!]").fully_unwrapped.name).to eq "Int"
            expect(type_ref("[[[[Int!]]]]").fully_unwrapped.name).to eq "Int"
          end
        end

        describe "#scalar_type_needing_grouped_by_object?" do
          let(:type_name_overrides) do
            {
              "Date" => "MyDate",
              "DateTime" => "MyDateTime",
              "LocalTime" => "MyLocalTime",
              "Widget" => "MyWidget"
            }
          end

          it "returns true for Date and DateTime types only" do
            expect(type_ref("Date").scalar_type_needing_grouped_by_object?).to eq(true)
            expect(type_ref("DateTime").scalar_type_needing_grouped_by_object?).to eq(true)

            expect(type_ref("LocalTime").scalar_type_needing_grouped_by_object?).to eq(false)
            expect(type_ref("Widget").scalar_type_needing_grouped_by_object?).to eq(false)
          end

          it "returns true for Date and DateTime types only when overridden" do
            expect(type_ref("MyDate").scalar_type_needing_grouped_by_object?).to eq(true)
            expect(type_ref("MyDateTime").scalar_type_needing_grouped_by_object?).to eq(true)

            expect(type_ref("MyLocalTime").scalar_type_needing_grouped_by_object?).to eq(false)
            expect(type_ref("MyWidget").scalar_type_needing_grouped_by_object?).to eq(false)
          end
        end

        describe "#with_reverted_override" do
          let(:type_name_overrides) do
            {
              "Date" => "MyDate",
              "DateTime" => "MyDateTime",
              "Widget" => "MyWidget"
            }
          end

          it "returns a new TypeReference with the override reverted" do
            expect(type_ref("MyDate").with_reverted_override.name).to eq "Date"
            expect(type_ref("MyDateTime").with_reverted_override.name).to eq "DateTime"
            expect(type_ref("MyWidget").with_reverted_override.name).to eq "Widget"
          end

          it "returns the type if no overrides are present" do
            expect(type_ref("Date").with_reverted_override.name).to eq "Date"
            expect(type_ref("DateTime").with_reverted_override.name).to eq "DateTime"
            expect(type_ref("Widget").with_reverted_override.name).to eq "Widget"
          end
        end

        shared_context "enforce all STATIC_FORMAT_NAME_BY_CATEGORY entries are tested" do
          before(:context) do
            @tested_derived_type_formats = ::Set.new
          end

          after(:context) do
            untested_formats = TypeReference::STATIC_FORMAT_NAME_BY_CATEGORY.values.to_set - @tested_derived_type_formats
            expect(untested_formats).to be_empty, "Expected all `TypeReference::STATIC_FORMAT_NAME_BY_CATEGORY` to be covered by the tests " \
              "in the `#{self.class.metadata[:description]}` context, but #{untested_formats.size} were not: #{untested_formats.to_a.inspect}."
          end
        end

        describe "determining the kind of type" do
          include_context "enforce all STATIC_FORMAT_NAME_BY_CATEGORY entries are tested"

          %w[
            AggregatedValues GroupedBy Aggregation AggregationConnection AggregationEdge
            Connection Edge FilterInput Highlights ListFilterInput FieldsListFilterInput
            ListElementFilterInput SubAggregation AggregationSubAggregations
          ].each do |suffix|
            it "considers a `*#{suffix}` type to be an object instead of a leaf" do
              expect_to_be_object suffix
            end
          end

          it "considers a `*SortOrder` type to be an enum leaf instead of an object" do
            expect_to_be_leaf "SortOrder", enum: true, format: :SortOrder
          end

          it "considers a `*SortOrderInput` type to be an enum leaf instead of an object" do
            expect_to_be_leaf "SortOrderInput", enum: true, format: :SortOrder
          end

          it "considers a scalr type to be a scalar leaf instead of an object" do
            type = type_ref("JsonSafeLong")
            expect(type.object?).to be false
            expect(type.leaf?).to be true
            expect(type.enum?).to be false

            type = type_ref("JsonSafeLong!")
            expect(type.object?).to be false
            expect(type.leaf?).to be true
            expect(type.enum?).to be false
          end

          it "considers both input and output forms of an enum to be an enum" do
            type = type_ref("DateTimeUnit")
            expect(type.enum?).to be true

            type = type_ref("DateTimeUnitInput")
            expect(type.enum?).to be true
          end

          context "when dealing with a type that has been renamed" do
            it "correctly detects a renamed object type" do
              type = type_ref("RingValuesAggregated")
              expect(type_name_overrides.values).to include(type.name)

              expect(type.object?).to be true
              expect(type.leaf?).to be false
              expect(type.enum?).to be false
            end

            it "correctly detects a renamed enum type" do
              type = type_ref("RingOrderSort")
              expect(type_name_overrides.values).to include(type.name)

              expect(type.object?).to be false
              expect(type.leaf?).to be true
              expect(type.enum?).to be true

              type = type_ref("RingOrderSortInput")
              expect(type_name_overrides.values).to include(type.name)

              expect(type.object?).to be false
              expect(type.leaf?).to be true
              expect(type.enum?).to be true
            end
          end

          it "is unsure about an `*Input` type since it could be an enum or an object" do
            type_ref = type_ref_for("Input", format: :InputEnum)

            expect_cannot_resolve_failures_for(type_ref)
          end

          it "raises an error if it cannot figure it out due to the type not being defined yet" do
            type = type_ref("Unknown")

            expect_cannot_resolve_failures_for(type)
          end

          def expect_to_be_object(suffix, format: suffix.to_sym)
            type = type_ref_for(suffix, format: format)
            expect(type.object?).to be true
            expect(type.leaf?).to be false

            type = type_ref_for("#{suffix}!", format: format)
            expect(type.object?).to be true
            expect(type.leaf?).to be false
            expect(type.enum?).to be false
          end

          def expect_to_be_leaf(suffix, enum:, format: suffix.to_sym)
            type = type_ref_for(suffix, format: format)
            expect(type.object?).to be false
            expect(type.leaf?).to be true
            expect(type.enum?).to be enum

            type = type_ref_for("#{suffix}!", format: format)
            expect(type.object?).to be false
            expect(type.leaf?).to be true
            expect(type.enum?).to be enum
          end

          def type_ref_for(suffix, format:)
            @tested_derived_type_formats << format
            type_ref("MyType#{suffix}")
          end

          def expect_cannot_resolve_failures_for(type)
            expect { type.object? }.to raise_error a_string_including("Type `#{type.name}` cannot be resolved")
            expect { type.leaf? }.to raise_error a_string_including("Type `#{type.name}` cannot be resolved")
            expect { type.enum? }.to raise_error a_string_including("Type `#{type.name}` cannot be resolved")
          end
        end

        describe "derived type names" do
          include_context "SchemaDefinitionHelpers"
          attr_reader :state, :defined_graphql_types

          before(:context) do
            result = define_widget_and_color_schema
            @result = result
            @state = result.state
            schema_string_with_orphaned_types_dropped = ::GraphQL::Schema.from_definition(result.graphql_schema_string).to_definition
            @defined_graphql_types = ::GraphQL::Schema.from_definition(schema_string_with_orphaned_types_dropped).types.keys.to_set
          end

          describe "#as_parent_aggregation" do
            it "raises an exception when `parent_doc_types` is passed as an empty array" do
              type = type_ref("Widget")
              expect {
                type.as_parent_aggregation(parent_doc_types: [])
              }.to raise_error Errors::SchemaError, a_string_including("`parent_doc_types` must not be empty")
            end
          end

          describe "#as_sub_aggregation" do
            it "preserves non-nullability when converting to the derived type" do
              type_ref = state.type_ref("Widget!")

              expect(type_ref.as_sub_aggregation(parent_doc_types: ["Manufacturer"]).name).to eq "ManufacturerWidgetSubAggregation!"
            end

            it "preserves a list wrapping when converting to the derived type" do
              type_ref = state.type_ref("[Widget]")

              expect(type_ref.as_sub_aggregation(parent_doc_types: ["Manufacturer"]).name).to eq "[ManufacturerWidgetSubAggregation]"
            end

            it "preserves multiple layers of list and non-null wrappings when converting to the derived type" do
              type_ref = state.type_ref("[[Widget!]]!")

              expect(type_ref.as_sub_aggregation(parent_doc_types: ["Manufacturer"]).name).to eq "[[ManufacturerWidgetSubAggregation!]]!"
            end
          end

          describe "#as_aggregation_sub_aggregations" do
            it "preserves non-nullability when converting to the derived type" do
              type_ref = state.type_ref("Widget!")

              expect(type_ref.as_aggregation_sub_aggregations.name).to eq "WidgetAggregationSubAggregations!"
            end

            it "preserves a list wrapping when converting to the derived type" do
              type_ref = state.type_ref("[Widget]")

              expect(type_ref.as_aggregation_sub_aggregations.name).to eq "[WidgetAggregationSubAggregations]"
            end

            it "preserves multiple layers of list and non-null wrappings when converting to the derived type" do
              type_ref = state.type_ref("[[Widget!]]!")

              expect(type_ref.as_aggregation_sub_aggregations.name).to eq "[[WidgetAggregationSubAggregations!]]!"
            end
          end

          shared_examples_for "a static derived name format" do |source_type:, category:, suffix:, offer_predicate:, suffix_on_defined_type: suffix|
            let(:type_ref) { state.type_ref(source_type) }
            let(:expected_type_name) { source_type + suffix }

            it "generates the expected type name from `#as_static_derived_type(:#{category})`" do
              derived_type_ref = type_ref.as_static_derived_type(category)

              expect(derived_type_ref).to be_a(TypeReference)
              expect(derived_type_ref.name).to eq(expected_type_name)
            end

            it "offers a `#as_#{category}` method that returns a name like `{source_type}#{suffix}`" do
              derived_type_ref = type_ref.public_send(:"as_#{category}")

              expect(derived_type_ref).to be_a(TypeReference)
              expect(derived_type_ref.name).to eq(expected_type_name)
            end

            it "preserves non-nullability when converting to the derived type" do
              type_ref = state.type_ref("#{source_type}!")

              expect(type_ref.as_static_derived_type(category).name).to eq("#{expected_type_name}!")
              expect(type_ref.public_send(:"as_#{category}").name).to eq("#{expected_type_name}!")
            end

            it "preserves a list wrapping when converting to the derived type" do
              type_ref = state.type_ref("[#{source_type}]")

              expect(type_ref.as_static_derived_type(category).name).to eq("[#{expected_type_name}]")
              expect(type_ref.public_send(:"as_#{category}").name).to eq("[#{expected_type_name}]")
            end

            it "preserves multiple layers of list and non-null wrappings when converting to the derived type" do
              type_ref = state.type_ref("[[#{source_type}!]]!")

              expect(type_ref.as_static_derived_type(category).name).to eq("[[#{expected_type_name}!]]!")
              expect(type_ref.public_send(:"as_#{category}").name).to eq("[[#{expected_type_name}!]]!")
            end

            it "generates a type named `{source_type}#{suffix_on_defined_type}` in the GraphQL schema string" do
              expect(defined_graphql_types).to include(source_type + suffix_on_defined_type)
            end

            if offer_predicate
              it "indicates it is in the `:#{category}` via `##{category}?`" do
                derived_type_ref = type_ref.as_static_derived_type(category)

                expect(derived_type_ref.public_send(:"#{category}?")).to be true
                expect(type_ref.public_send(:"#{category}?")).to be false
              end
            else
              it "does not offer a `##{category}?` predicate" do
                expect(type_ref).not_to respond_to(:"#{category}?")
              end
            end
          end

          TypeReference::STATIC_FORMAT_NAME_BY_CATEGORY.except(:sort_order, :input_enum, :list_filter_input, :list_element_filter_input).each do |category, format_name|
            describe "the `:#{category}` derived type" do
              include_examples "a static derived name format",
                source_type: "Widget",
                category: category,
                suffix: format_name.to_s,
                offer_predicate: false
            end
          end

          describe "the `:list_filter_input` derived type" do
            include_examples "a static derived name format",
              source_type: "Widget",
              category: :list_filter_input,
              suffix: "ListFilterInput",
              offer_predicate: true
          end

          describe "the `:list_element_filter_input` derived type" do
            include_examples "a static derived name format",
              source_type: "Color",
              category: :list_element_filter_input,
              suffix: "ListElementFilterInput",
              offer_predicate: true
          end

          describe "the `:input_enum` derived type" do
            include_examples "a static derived name format",
              category: :input_enum,
              source_type: "Color",
              suffix: "Input",
              offer_predicate: false
          end

          describe "the `:sort_order` derived type" do
            include_examples "a static derived name format",
              category: :sort_order,
              source_type: "Widget",
              suffix: "SortOrder",
              suffix_on_defined_type: "SortOrderInput",
              offer_predicate: false
          end

          describe "#to_final_form" do
            it "returns the existing `TypeReference` instance if no customizations apply to it" do
              ref = type_ref("MyTypeGroupedBy")

              expect(ref.to_final_form).to be(ref)
            end

            it "uses the configured name override if one is configured for this type" do
              ref = type_ref("MyTypeGroupedBy", type_name_overrides: {"MyTypeGroupedBy" => "MyTypeGroupedByAlt"})

              expect(ref.to_final_form.name).to eq "MyTypeGroupedByAlt"
            end

            it "preserves wrappings" do
              ref = type_ref("[MyTypeGroupedBy!]", type_name_overrides: {"MyTypeGroupedBy" => "MyTypeGroupedByAlt"})

              expect(ref.to_final_form.name).to eq "[MyTypeGroupedByAlt!]"
            end

            it "converts to the input enum form if the type is an enum type and `as_input: true` was passed" do
              ref = type_ref("[WidgetSortingOrder!]", derived_type_name_formats: {InputEnum: "%{base}Inp", SortOrder: "%{base}SortingOrder"})

              expect(ref.to_final_form(as_input: true).name).to eq "[WidgetSortingOrderInp!]"
              expect(ref.to_final_form.name).to eq "[WidgetSortingOrder!]"
            end

            it "applies a name override to the converted input type when one is configured" do
              ref = type_ref(
                "[WidgetSortingOrder!]",
                derived_type_name_formats: {InputEnum: "%{base}Inp", SortOrder: "%{base}SortingOrder"},
                type_name_overrides: {WidgetSortingOrderInp: "InpSortingWidgetOrder"}
              )

              expect(ref.to_final_form(as_input: true).name).to eq "[InpSortingWidgetOrder!]"
            end

            it "raises if it cannot determine if it is an enum with `as_input: true`" do
              ref = type_ref("SomeType")

              expect(ref.to_final_form(as_input: false).name).to eq "SomeType"
              expect(ref.to_final_form.name).to eq "SomeType"
              expect { ref.to_final_form(as_input: true) }.to raise_error a_string_including("Type `SomeType` cannot be resolved")
            end

            it "uses a configured name override, regardless of `as_input`, when a type isn't registered under the old name" do
              api = api(type_name_overrides: {"OldName" => "NewName"})
              api.object_type("NewName")

              ref = api.state.type_ref("OldName")
              expect(ref.to_final_form(as_input: false).name).to eq "NewName"
              expect(ref.to_final_form(as_input: true).name).to eq "NewName"
            end

            def api(type_name_overrides: {}, derived_type_name_formats: {})
              API.new(
                SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: "snake_case"),
                true,
                type_name_overrides: type_name_overrides,
                derived_type_name_formats: derived_type_name_formats
              )
            end

            def type_ref(name, type_name_overrides: {}, derived_type_name_formats: {})
              api(type_name_overrides: type_name_overrides, derived_type_name_formats: derived_type_name_formats)
                .state
                .type_ref(name)
            end
          end

          context "when we change the derived type formats" do
            include_context "enforce all STATIC_FORMAT_NAME_BY_CATEGORY entries are tested"

            before(:context) do
              derived_type_name_formats = TypeNamer::DEFAULT_FORMATS.transform_values do |format|
                mangle_format(format)
              end

              result = define_widget_and_color_schema(derived_type_name_formats: derived_type_name_formats)
              @state = result.state
              @defined_graphql_types = ::GraphQL::Schema.from_definition(result.graphql_schema_string).types.keys.sort.to_set
            end

            shared_examples_for "a static format" do |category:, format:, suffix:, source_type:|
              # Note: the test here doesn't really exercise `TypeReference` -- rather, it validates that all the other parts of
              # `elasticgraph-schema_definition` use `TypeReference` to generate these derived type names and don't hardcode
              # their own derived type suffixes.
              it "generates the `:#{category}` type using an alternate format rather than the standard one" do
                @tested_derived_type_formats << format
                expect(defined_graphql_types).to include("#{source_type}#{mangle_format(suffix)}").and exclude("#{source_type}#{suffix}")
              end
            end

            TypeReference::STATIC_FORMAT_NAME_BY_CATEGORY.except(:list_element_filter_input, :sort_order, :input_enum).each do |category, format_name|
              include_examples "a static format",
                category: category,
                format: format_name,
                suffix: format_name.to_s,
                source_type: "Widget"
            end

            include_examples "a static format",
              category: :list_element_filter_input,
              format: :ListElementFilterInput,
              suffix: "ListElementFilterInput",
              # The `ListElementFilterInput` type is only generated for a leaf type like `Color`, not for object types like `Widget`.
              source_type: "Color"

            include_examples "a static format",
              category: :input_enum,
              format: :InputEnum,
              suffix: "Input",
              source_type: "Color"

            include_examples "a static format",
              category: :sort_order,
              format: :SortOrder,
              suffix: "SortOrderInput",
              source_type: "Widget"

            def mangle_format(format)
              # Deal with compound formats...
              format = format.sub("Aggregation", "Aggregation2")
              format = format.sub("SortOrder", "SortOrder2")

              format.end_with?("2") ? format : "#{format}2"
            end
          end

          def define_widget_and_color_schema(derived_type_name_formats: {})
            schema_elements = SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: "snake_case")
            define_schema_with_schema_elements(schema_elements, derived_type_name_formats: derived_type_name_formats) do |api|
              api.enum_type "Color" do |t|
                t.values "RED", "GREEN", "BLUE"
              end

              api.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "colors", "[Color!]!"
                t.paginated_collection_field "colors_paginated", "Color"
                t.field "color", "Color"
                t.field "cost", "Int"
                # Some derived types are only generated when a type has nested fields.
                t.field "is_nested", "[IsNested!]!" do |f|
                  f.mapping type: "nested"
                end
                t.index "widgets"
              end

              api.object_type "IsNested" do |t|
                t.field "something", "String"
              end

              api.object_type "HasNested" do |t|
                t.field "id", "ID"
                t.field "string", "String"
                t.field "int", "Int"

                # Some derived types are only generated when a type is used by a nested field.
                t.field "widgets_nested", "[Widget!]!" do |f|
                  f.mapping type: "nested"
                end

                # Some derived types are only generated when a type is used by a a list of `object` field.
                t.field "widgets_object", "[Widget!]!" do |f|
                  f.mapping type: "object"
                end
                t.index "has_nested"
              end

              api.on_root_query_type do |t|
                t.field "time", "DateTime" do |f|
                  date_time_unit_input_type_name = api.state.type_ref("DateTimeUnit").as_input_enum
                  f.argument "offsetUnit", "#{date_time_unit_input_type_name}!"
                end
              end
            end
          end
        end

        def type_ref(name)
          state.type_ref(name)
        end
      end
    end
  end
end
