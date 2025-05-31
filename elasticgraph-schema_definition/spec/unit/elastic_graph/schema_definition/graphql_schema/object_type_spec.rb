# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "graphql_schema_spec_support"
require_relative "implements_shared_examples"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "GraphQL schema generation", "#object_type" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "can generate a simple embedded type (no directives)" do
          result = object_type "WidgetOptions" do |t|
            t.field "size", "String!"
            t.field "main_color", "String"
          end

          expect(result).to eq(<<~EOS)
            type WidgetOptions {
              size: String!
              main_color: String
            }
          EOS
        end

        it "generates documentation comments when the caller calls `documentation` on a type or field" do
          result = object_type "WidgetOptions" do |t|
            t.documentation "Options for a widget."

            t.field "size", "String!" do |f|
              f.documentation "The size of the widget."
            end

            t.field "color", "String!" do |f|
              f.documentation <<~EOS
                Multiline strings
                are also formatted correctly!
              EOS
            end
          end

          expect(result).to eq(<<~EOS)
            """
            Options for a widget.
            """
            type WidgetOptions {
              """
              The size of the widget.
              """
              size: String!
              """
              Multiline strings
              are also formatted correctly!
              """
              color: String!
            }
          EOS
        end

        it "respects a configured type name override" do
          result = define_schema(type_name_overrides: {"Widget" => "Gadget"}) do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "widgets"
            end
          end

          expect(type_def_from(result, "Widget")).to eq nil
          expect(type_def_from(result, "Gadget")).to eq(<<~EOS.strip)
            type Gadget {
              id: ID
              name: String
            }
          EOS

          expect(type_def_from(result, "GadgetFilterInput")).not_to eq nil
          expect(type_def_from(result, "GadgetConnection")).not_to eq nil
          expect(type_def_from(result, "GadgetEdge")).not_to eq nil

          # Verify that there are _no_ `Widget` types defined
          expect(result.lines.grep(/Widgedt/)).to be_empty
        end

        it "raises a clear error when the type name is not formatted correctly" do
          expect {
            object_type("Invalid.Name") {}
          }.to raise_invalid_graphql_name_error_for("Invalid.Name")
        end

        it "raises a clear error when the type name is not formatted correctly" do
          expect {
            object_type "WidgetOptions" do |t|
              t.field "invalid.name", "String!"
            end
          }.to raise_invalid_graphql_name_error_for("invalid.name")
        end

        it "fails with a clear error when a field is defined with unrecognized options" do
          expect {
            object_type "WidgetOptions" do |t|
              t.field "size", "String!", invalid_option: 3
            end
          }.to raise_error(a_string_including("invalid_option"))
        end

        it "raises a clear exception if an embedded type is recursively self-referential without using a relation" do
          expect {
            define_schema do |s|
              s.object_type "Type1" do |t|
                t.field "t2", "Type2"
              end

              s.object_type "Type2" do |t|
                t.field "t3", "Type3"
              end

              s.object_type "Type3" do |t|
                t.field "t1", "Type1"
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including('The set of ["Type2", "Type3", "Type1"] forms a circular reference chain')
        end

        it "allows multiple types to be defined in one evaluation block" do
          result = define_schema do |api|
            api.object_type "T1" do |t|
              t.field "size", "String!"
            end

            api.object_type "T2" do |t|
              t.field "size", "String!"
            end
          end

          expect(type_def_from(result, "T1")).to eq(<<~EOS.chomp)
            type T1 {
              size: String!
            }
          EOS

          expect(type_def_from(result, "T2")).to eq(<<~EOS.chomp)
            type T2 {
              size: String!
            }
          EOS
        end

        it "produces a clear error when the same field is defined multiple times" do
          expect {
            object_type "WidgetOptions" do |t|
              t.field "size", "String!"
              t.field "size", "String"
            end
          }.to raise_error Errors::SchemaError, a_string_including("Duplicate", "WidgetOptions", "field", "size")
        end

        %w[not all_of any_of any_satisfy].each do |field_name|
          it "produces a clear error if a `#{field_name}` field is defined since that will conflict with the filtering operators" do
            expect {
              object_type "WidgetOptions" do |t|
                t.field schema_elements.public_send(field_name), "String"
              end
            }.to raise_error Errors::SchemaError, a_string_including("WidgetOptions.#{schema_elements.public_send(field_name)}", "reserved")
          end
        end

        it "raises a clear error when the same type is defined multiple times" do
          expect {
            define_schema do |api|
              api.object_type "WidgetOptions" do |t|
                t.field "size", "String!"
                t.field "main_color", "String"
              end

              api.object_type "WidgetOptions" do |t|
                t.field "size2", "String!"
                t.field "main_color2", "String"
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("Duplicate", "WidgetOptions")
        end

        it "allows a type to be defined with no fields, since the GraphQL gem allows it" do
          result = object_type("WidgetOptions")

          expect(result.delete("\n")).to eq("type WidgetOptions {}")
        end

        describe "#implements" do
          include_examples "#implements",
            graphql_definition_keyword: "type",
            ruby_definition_method: :object_type
        end

        describe "directives" do
          it "raises a clear error when the directive name is not formatted correctly" do
            expect {
              object_type "WidgetOptions" do |t|
                t.directive "invalid.name"
              end
            }.to raise_invalid_graphql_name_error_for("invalid.name")
          end

          it "can be added to the type with no arguments" do
            result = define_schema do |schema|
              schema.raw_sdl "directive @foo on OBJECT"
              schema.raw_sdl "directive @bar on OBJECT"

              schema.object_type "WidgetOptions" do |t|
                t.directive "foo"
                t.directive "bar"
                t.field "size", "String!"
                t.field "main_color", "String"
              end
            end

            expect(type_def_from(result, "WidgetOptions")).to eq(<<~EOS.strip)
              type WidgetOptions @foo @bar {
                size: String!
                main_color: String
              }
            EOS
          end

          it "can be added to the type with arguments" do
            result = define_schema do |schema|
              schema.raw_sdl "directive @foo(size: Int) on OBJECT"
              schema.raw_sdl "directive @bar(color: String) on OBJECT"

              schema.object_type "WidgetOptions" do |t|
                t.directive "foo", size: 1
                t.directive "foo", size: 3
                t.directive "bar", color: "red"
                t.field "size", "String!"
                t.field "main_color", "String"
              end
            end

            expect(type_def_from(result, "WidgetOptions")).to eq(<<~EOS.strip)
              type WidgetOptions @foo(size: 1) @foo(size: 3) @bar(color: "red") {
                size: String!
                main_color: String
              }
            EOS
          end

          it "can be added to fields, with no directive arguments" do
            result = define_schema do |schema|
              schema.raw_sdl "directive @foo on FIELD_DEFINITION"
              schema.raw_sdl "directive @bar on FIELD_DEFINITION"

              schema.object_type "WidgetOptions" do |t|
                t.field "size", "String!" do |f|
                  f.directive "foo"
                  f.directive "bar"
                end
              end
            end

            expect(type_def_from(result, "WidgetOptions")).to eq(<<~EOS.strip)
              type WidgetOptions {
                size: String! @foo @bar
              }
            EOS
          end

          it "can be added to fields, with directive arguments" do
            result = define_schema do |schema|
              schema.raw_sdl "directive @foo(size: Int) on FIELD_DEFINITION"
              schema.raw_sdl "directive @bar(color: String) on FIELD_DEFINITION"

              schema.object_type "WidgetOptions" do |t|
                t.field "size", "String!" do |f|
                  f.directive "foo", size: 1
                  f.directive "foo", size: 3
                  f.directive "bar", color: "red"
                end
              end
            end

            expect(type_def_from(result, "WidgetOptions")).to eq(<<~EOS.strip)
              type WidgetOptions {
                size: String! @foo(size: 1) @foo(size: 3) @bar(color: "red")
              }
            EOS
          end
        end

        describe "#on_each_generated_schema_element" do
          it "applies the given block to each schema element generated for this field, supporting customizations across all of them" do
            result = define_schema do |api|
              api.raw_sdl "directive @external on FIELD_DEFINITION | ENUM_VALUE | INPUT_FIELD_DEFINITION"

              api.object_type "Money" do |t|
                t.field "amount", "Int"
                t.field "currency", "String"
              end

              api.object_type "Widget" do |t|
                t.field "id", "ID", groupable: false, aggregatable: false, highlightable: false
                t.field "cost", "Int", highlightable: true do |f|
                  f.on_each_generated_schema_element do |gse|
                    gse.directive "deprecated"
                  end

                  f.on_each_generated_schema_element do |gse|
                    gse.directive "external"
                  end
                end

                t.field "costs", "[Money]" do |f|
                  f.mapping type: "nested"
                  f.on_each_generated_schema_element do |gse|
                    gse.directive "deprecated"
                  end
                end

                t.index "widgets"
              end
            end

            expect(type_def_from(result, "Widget")).to eq(<<~EOS.strip)
              type Widget {
                id: ID
                cost: Int @deprecated @external
                costs: [Money] @deprecated
              }
            EOS

            expect(filter_type_from(result, "Widget")).to eq(<<~EOS.strip)
              input WidgetFilterInput {
                #{schema_elements.any_of}: [WidgetFilterInput!]
                #{schema_elements.all_of}: [WidgetFilterInput!]
                not: WidgetFilterInput
                id: IDFilterInput
                cost: IntFilterInput @deprecated @external
                costs: MoneyListFilterInput @deprecated
              }
            EOS

            expect(aggregated_values_type_from(result, "Widget")).to eq(<<~EOS.strip)
              type WidgetAggregatedValues {
                cost: IntAggregatedValues @deprecated @external
              }
            EOS

            expect(grouped_by_type_from(result, "Widget")).to eq(<<~EOS.strip)
              type WidgetGroupedBy {
                cost: Int @deprecated @external
              }
            EOS

            expect(highlights_type_from(result, "Widget")).to eq(<<~EOS.strip)
              type WidgetHighlights {
                cost: [String!]! @deprecated @external
                costs: MoneyHighlights @deprecated
              }
            EOS

            expect(sort_order_type_from(result, "Widget")).to eq(<<~EOS.strip)
              enum WidgetSortOrderInput {
                id_ASC
                id_DESC
                cost_ASC @deprecated @external
                cost_DESC @deprecated @external
              }
            EOS

            expect(aggregation_sub_aggregations_type_from(result, "Widget")).to eq(<<~EOS.strip)
              type WidgetAggregationSubAggregations {
                costs(
                  #{schema_elements.filter}: MoneyFilterInput
                  #{schema_elements.first}: Int): WidgetMoneySubAggregationConnection @deprecated
              }
            EOS
          end
        end

        describe "relation fields" do
          it "can define a has-one relation using `relates_to_one`" do
            result = define_schema do |schema|
              schema.object_type "Widget" do |t|
                t.relates_to_one "inventor", "Person", via: "inventor_id", dir: :out do |f|
                  f.documentation "The inventor of this Widget."
                end
              end

              schema.object_type "Person" do |t|
                t.field "id", "ID"
                t.index "people"
              end
            end

            expect(type_def_from(result, "Widget", include_docs: true)).to eq(<<~EOS.strip)
              type Widget {
                """
                The inventor of this Widget.
                """
                inventor: Person
              }
            EOS
          end

          it "can define a has-many relation using `relates_to_many`" do
            pre_def = ->(api) {
              api.object_type "Person" do |t|
                t.field "id", "ID"
                t.field "name", "String", filterable: true, sortable: true
                t.index "people"
              end
            }

            result = object_type "Widget", pre_def: pre_def do |t|
              t.relates_to_many "inventors", "Person", via: "inventor_ids", dir: :out, singular: "inventor" do |f|
                f.documentation "The collection of inventors of this Widget."
              end
            end

            expect(result).to eq(<<~EOS)
              type Widget {
                """
                The collection of inventors of this Widget.
                """
                inventors(
                  """
                  Used to filter the returned `inventors` based on the provided criteria.
                  """
                  #{schema_elements.filter}: PersonFilterInput
                  """
                  Used to specify how the returned `inventors` should be sorted.
                  """
                  #{schema_elements.order_by}: [PersonSortOrderInput!]
                  """
                  Used in conjunction with the `after` argument to forward-paginate through the `inventors`.
                  When provided, limits the number of returned results to the first `n` after the provided
                  `after` cursor (or from the start of the `inventors`, if no `after` cursor is provided).

                  See the [Relay GraphQL Cursor Connections
                  Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                  """
                  #{schema_elements.first}: Int
                  """
                  Used to forward-paginate through the `inventors`. When provided, the next page after the
                  provided cursor will be returned.

                  See the [Relay GraphQL Cursor Connections
                  Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                  """
                  #{schema_elements.after}: Cursor
                  """
                  Used in conjunction with the `before` argument to backward-paginate through the `inventors`.
                  When provided, limits the number of returned results to the last `n` before the provided
                  `before` cursor (or from the end of the `inventors`, if no `before` cursor is provided).

                  See the [Relay GraphQL Cursor Connections
                  Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                  """
                  #{schema_elements.last}: Int
                  """
                  Used to backward-paginate through the `inventors`. When provided, the previous page before the
                  provided cursor will be returned.

                  See the [Relay GraphQL Cursor Connections
                  Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                  """
                  #{schema_elements.before}: Cursor): PersonConnection
                """
                Aggregations over the `inventors` data:

                > The collection of inventors of this Widget.
                """
                #{correctly_cased "inventor_aggregations"}(
                  """
                  Used to filter the `Person` documents that get aggregated over based on the provided criteria.
                  """
                  filter: PersonFilterInput
                  """
                  Used in conjunction with the `after` argument to forward-paginate through the `#{correctly_cased "inventor_aggregations"}`.
                  When provided, limits the number of returned results to the first `n` after the provided
                  `after` cursor (or from the start of the `#{correctly_cased "inventor_aggregations"}`, if no `after` cursor is provided).

                  See the [Relay GraphQL Cursor Connections
                  Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                  """
                  first: Int
                  """
                  Used to forward-paginate through the `#{correctly_cased "inventor_aggregations"}`. When provided, the next page after the
                  provided cursor will be returned.

                  See the [Relay GraphQL Cursor Connections
                  Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                  """
                  after: Cursor
                  """
                  Used in conjunction with the `before` argument to backward-paginate through the `#{correctly_cased "inventor_aggregations"}`.
                  When provided, limits the number of returned results to the last `n` before the provided
                  `before` cursor (or from the end of the `#{correctly_cased "inventor_aggregations"}`, if no `before` cursor is provided).

                  See the [Relay GraphQL Cursor Connections
                  Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                  """
                  last: Int
                  """
                  Used to backward-paginate through the `#{correctly_cased "inventor_aggregations"}`. When provided, the previous page before the
                  provided cursor will be returned.

                  See the [Relay GraphQL Cursor Connections
                  Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                  """
                  before: Cursor): PersonAggregationConnection
              }
            EOS
          end

          it "respects a type name override of the related type when generating the fields for a `relates_to_many`" do
            results = define_schema(type_name_overrides: {Component: "Part"}) do |schema|
              schema.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.relates_to_many "components", "Component", via: "widget_id", dir: :in, singular: "component"
                t.index "widgets"
              end

              schema.object_type "Component" do |t|
                t.field "id", "ID!"
                t.index "widgets"
              end
            end

            expect(type_def_from(results, "Widget")).to eq(<<~EOS.strip)
              type Widget {
                id: ID!
                components(
                  #{schema_elements.filter}: PartFilterInput
                  #{schema_elements.order_by}: [PartSortOrderInput!]
                  #{schema_elements.first}: Int
                  #{schema_elements.after}: Cursor
                  #{schema_elements.last}: Int
                  #{schema_elements.before}: Cursor): PartConnection
                #{correctly_cased "component_aggregations"}(
                  #{schema_elements.filter}: PartFilterInput
                  #{schema_elements.first}: Int
                  #{schema_elements.after}: Cursor
                  #{schema_elements.last}: Int
                  #{schema_elements.before}: Cursor): PartAggregationConnection
              }
            EOS
          end

          it "omits the `order_by` arg on a has-many when the type is not sortable" do
            pre_def = ->(api) {
              api.object_type "Person" do |t|
                t.field "id", "ID", sortable: false
                t.index "people"
                t.field "name", "String", filterable: true, sortable: false
              end
            }

            result = object_type "Widget", pre_def: pre_def, include_docs: false do |t|
              t.relates_to_many "inventors", "Person", via: "inventor_ids", dir: :out, singular: "inventor"
            end

            expect(result).to start_with(<<~EOS)
              type Widget {
                inventors(
                  #{schema_elements.filter}: PersonFilterInput
                  #{schema_elements.first}: Int
                  #{schema_elements.after}: Cursor
                  #{schema_elements.last}: Int
                  #{schema_elements.before}: Cursor): PersonConnection
            EOS
          end

          it "omits the `filter` arg on a has-many when the type is not filterable" do
            pre_def = ->(api) {
              api.object_type "Person" do |t|
                t.field "id", "ID", filterable: false
                t.index "people"
                t.field "name", "String", filterable: false, sortable: true
              end
            }

            result = object_type "Widget", pre_def: pre_def, include_docs: false do |t|
              t.relates_to_many "inventors", "Person", via: "inventor_ids", dir: :out, singular: "inventor"
            end

            expect(result).to start_with(<<~EOS)
              type Widget {
                inventors(
                  #{schema_elements.order_by}: [PersonSortOrderInput!]
                  #{schema_elements.first}: Int
                  #{schema_elements.after}: Cursor
                  #{schema_elements.last}: Int
                  #{schema_elements.before}: Cursor): PersonConnection
            EOS
          end
        end

        it "can generate a simple indexed type (with just `name`)" do
          result = object_type "Widget" do |t|
            t.field "id", "ID"
            t.index "widgets"
          end

          expect(result).to eq(<<~EOS)
            type Widget {
              id: ID
            }
          EOS
        end

        describe "custom shard routing options" do
          it "documents the importance of filtering on the custom routing field on the parent type" do
            result = object_type "Widget", include_docs: true do |t|
              t.documentation "A widget."
              t.field "id", "ID"
              t.field "user_id", "ID" do |f|
                f.json_schema nullable: false
              end

              t.index "widgets" do |i|
                i.route_with "user_id"
              end
            end

            expect(result).to eq(<<~EOS)
              """
              A widget.

              For more performant queries on this type, please filter on `user_id` if possible.
              """
              type Widget {
                id: ID
                user_id: ID
              }
            EOS
          end
        end

        def object_type(name, *args, pre_def: nil, include_docs: true, &block)
          result = define_schema do |api|
            pre_def&.call(api)
            api.object_type(name, *args, &block)
          end

          # We add a line break to match the expectations which use heredocs.
          type_def_from(result, name, include_docs: include_docs) + "\n"
        end
      end
    end
  end
end
