# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "graphql_schema_spec_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "GraphQL schema generation", "root Query type" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "generates a document search field and an aggregations field for each indexed type" do
          result = define_schema do |api|
            api.object_type "Person" do |t|
              t.implements "NamedEntity"
              t.field "id", "ID"
              t.field "name", "String"
              t.field "nationality", "String", filterable: false
              t.index "people"
            end

            api.object_type "Company" do |t|
              t.implements "NamedEntity"
              t.field "id", "ID"
              t.field "name", "String"
              t.field "stock_ticker", "String"
              t.index "companies"
            end

            api.interface_type "NamedEntity" do |t|
              t.field "id", "ID"
              t.field "name", "String"
            end

            api.union_type "Inventor" do |t|
              t.subtypes "Person", "Company"
            end

            api.object_type "Foo" do |t|
              t.field "id", "ID"
              t.field "size", "String"
            end

            api.object_type "Bar" do |t|
              t.field "id", "ID"
              t.field "length", "Int"
            end

            api.object_type "Class" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "classes"
            end

            api.union_type "FooOrBar" do |t|
              t.subtypes "Foo", "Bar"
              t.index "foos_or_bars"
            end
          end

          expect(type_def_from(result, "Query")).to eq(<<~EOS.strip)
            type Query {
              classes(
                filter: ClassFilterInput
                #{correctly_cased "order_by"}: [ClassSortOrderInput!]
                first: Int
                after: Cursor
                last: Int
                before: Cursor): ClassConnection
              #{correctly_cased "class_aggregations"}(
                filter: ClassFilterInput
                first: Int
                after: Cursor
                last: Int
                before: Cursor): ClassAggregationConnection
              companys(
                filter: CompanyFilterInput
                #{correctly_cased "order_by"}: [CompanySortOrderInput!]
                first: Int
                after: Cursor
                last: Int
                before: Cursor): CompanyConnection
              #{correctly_cased "company_aggregations"}(
                filter: CompanyFilterInput
                first: Int
                after: Cursor
                last: Int
                before: Cursor): CompanyAggregationConnection
              #{correctly_cased "foo_or_bars"}(
                filter: FooOrBarFilterInput
                #{correctly_cased "order_by"}: [FooOrBarSortOrderInput!]
                first: Int
                after: Cursor
                last: Int
                before: Cursor): FooOrBarConnection
              #{correctly_cased "foo_or_bar_aggregations"}(
                filter: FooOrBarFilterInput
                first: Int
                after: Cursor
                last: Int
                before: Cursor): FooOrBarAggregationConnection
              inventors(
                filter: InventorFilterInput
                #{correctly_cased "order_by"}: [InventorSortOrderInput!]
                first: Int
                after: Cursor
                last: Int
                before: Cursor): InventorConnection
              #{correctly_cased "inventor_aggregations"}(
                filter: InventorFilterInput
                first: Int
                after: Cursor
                last: Int
                before: Cursor): InventorAggregationConnection
              #{correctly_cased "named_entitys"}(
                filter: NamedEntityFilterInput
                #{correctly_cased "order_by"}: [NamedEntitySortOrderInput!]
                first: Int
                after: Cursor
                last: Int
                before: Cursor): NamedEntityConnection
              #{correctly_cased "named_entity_aggregations"}(
                filter: NamedEntityFilterInput
                first: Int
                after: Cursor
                last: Int
                before: Cursor): NamedEntityAggregationConnection
              persons(
                filter: PersonFilterInput
                #{correctly_cased "order_by"}: [PersonSortOrderInput!]
                first: Int
                after: Cursor
                last: Int
                before: Cursor): PersonConnection
              #{correctly_cased "person_aggregations"}(
                filter: PersonFilterInput
                first: Int
                after: Cursor
                last: Int
                before: Cursor): PersonAggregationConnection
            }
          EOS
        end

        it "allows the Query field names and directives to be customized on the indexed type definitions" do
          result = define_schema do |api|
            api.object_type "Person" do |t|
              t.implements "NamedEntity"
              t.root_query_fields plural: "people", singular: "human" do |f|
                f.directive "deprecated"
              end
              t.field "id", "ID"
              t.field "name", "String"
              t.field "nationality", "String", filterable: false
              t.index "people"
            end

            api.union_type "Inventor" do |t|
              t.root_query_fields plural: "inventorees"
              t.subtypes "Person"
            end

            api.interface_type "NamedEntity" do |t|
              t.root_query_fields plural: "named_entities"
              t.field "id", "ID"
              t.field "name", "String"
            end

            api.object_type "Widget" do |t|
              t.implements "NamedEntity"
              t.field "id", "ID"
              t.field "name", "String"
              t.index "widgets"
            end
          end

          expect(type_def_from(result, "Query")).to eq(<<~EOS.strip)
            type Query {
              inventorees(
                filter: InventorFilterInput
                #{correctly_cased "order_by"}: [InventorSortOrderInput!]
                first: Int
                after: Cursor
                last: Int
                before: Cursor): InventorConnection
              #{correctly_cased "inventor_aggregations"}(
                filter: InventorFilterInput
                first: Int
                after: Cursor
                last: Int
                before: Cursor): InventorAggregationConnection
              named_entities(
                filter: NamedEntityFilterInput
                #{correctly_cased "order_by"}: [NamedEntitySortOrderInput!]
                first: Int
                after: Cursor
                last: Int
                before: Cursor): NamedEntityConnection
              #{correctly_cased "named_entity_aggregations"}(
                filter: NamedEntityFilterInput
                first: Int
                after: Cursor
                last: Int
                before: Cursor): NamedEntityAggregationConnection
              people(
                filter: PersonFilterInput
                #{correctly_cased "order_by"}: [PersonSortOrderInput!]
                first: Int
                after: Cursor
                last: Int
                before: Cursor): PersonConnection @deprecated
              #{correctly_cased "human_aggregations"}(
                filter: PersonFilterInput
                first: Int
                after: Cursor
                last: Int
                before: Cursor): PersonAggregationConnection @deprecated
              widgets(
                filter: WidgetFilterInput
                #{correctly_cased "order_by"}: [WidgetSortOrderInput!]
                first: Int
                after: Cursor
                last: Int
                before: Cursor): WidgetConnection
              #{correctly_cased "widget_aggregations"}(
                filter: WidgetFilterInput
                first: Int
                after: Cursor
                last: Int
                before: Cursor): WidgetAggregationConnection
            }
          EOS
        end

        it "documents each field" do
          result = define_schema do |api|
            api.object_type "Person" do |t|
              t.root_query_fields plural: "people"
              t.field "id", "ID"
              t.field "name", "String"
              t.field "nationality", "String", filterable: false
              t.index "people"
            end
          end

          expect(type_def_from(result, "Query", include_docs: true)).to eq(<<~EOS.strip)
            """
            The query entry point for the entire schema.
            """
            type Query {
              """
              Fetches `Person`s based on the provided arguments.
              """
              people(
                """
                Used to filter the returned `people` based on the provided criteria.
                """
                filter: PersonFilterInput
                """
                Used to specify how the returned `people` should be sorted.
                """
                #{correctly_cased "order_by"}: [PersonSortOrderInput!]
                """
                Used in conjunction with the `after` argument to forward-paginate through the `people`.
                When provided, limits the number of returned results to the first `n` after the provided
                `after` cursor (or from the start of the `people`, if no `after` cursor is provided).

                See the [Relay GraphQL Cursor Connections
                Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                """
                first: Int
                """
                Used to forward-paginate through the `people`. When provided, the next page after the
                provided cursor will be returned.

                See the [Relay GraphQL Cursor Connections
                Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                """
                after: Cursor
                """
                Used in conjunction with the `before` argument to backward-paginate through the `people`.
                When provided, limits the number of returned results to the last `n` before the provided
                `before` cursor (or from the end of the `people`, if no `before` cursor is provided).

                See the [Relay GraphQL Cursor Connections
                Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                """
                last: Int
                """
                Used to backward-paginate through the `people`. When provided, the previous page before the
                provided cursor will be returned.

                See the [Relay GraphQL Cursor Connections
                Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                """
                before: Cursor): PersonConnection
              """
              Aggregations over the `people` data:

              > Fetches `Person`s based on the provided arguments.
              """
              #{correctly_cased "person_aggregations"}(
                """
                Used to filter the `Person` documents that get aggregated over based on the provided criteria.
                """
                filter: PersonFilterInput
                """
                Used in conjunction with the `after` argument to forward-paginate through the `#{correctly_cased "person_aggregations"}`.
                When provided, limits the number of returned results to the first `n` after the provided
                `after` cursor (or from the start of the `#{correctly_cased "person_aggregations"}`, if no `after` cursor is provided).

                See the [Relay GraphQL Cursor Connections
                Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                """
                first: Int
                """
                Used to forward-paginate through the `#{correctly_cased "person_aggregations"}`. When provided, the next page after the
                provided cursor will be returned.

                See the [Relay GraphQL Cursor Connections
                Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                """
                after: Cursor
                """
                Used in conjunction with the `before` argument to backward-paginate through the `#{correctly_cased "person_aggregations"}`.
                When provided, limits the number of returned results to the last `n` before the provided
                `before` cursor (or from the end of the `#{correctly_cased "person_aggregations"}`, if no `before` cursor is provided).

                See the [Relay GraphQL Cursor Connections
                Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                """
                last: Int
                """
                Used to backward-paginate through the `#{correctly_cased "person_aggregations"}`. When provided, the previous page before the
                provided cursor will be returned.

                See the [Relay GraphQL Cursor Connections
                Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
                """
                before: Cursor): PersonAggregationConnection
            }
          EOS
        end

        it "does not include field arguments that would provide unsupported capabilities" do
          result = define_schema do |api|
            api.object_type "Person" do |t|
              t.root_query_fields plural: "people"
              t.field "id", "ID!", sortable: false, filterable: false
              t.index "people"
            end
          end

          expect(type_def_from(result, "Query")).to eq(<<~EOS.strip)
            type Query {
              people(
                first: Int
                after: Cursor
                last: Int
                before: Cursor): PersonConnection
              #{correctly_cased "person_aggregations"}(
                first: Int
                after: Cursor
                last: Int
                before: Cursor): PersonAggregationConnection
            }
          EOS
        end

        it "does not generate derived types from the `Query` type, even if customized" do
          result = define_schema do |api|
            api.object_type "Person" do |t|
              t.root_query_fields plural: "people"
              t.field "id", "ID!", sortable: false, filterable: false
              t.index "people"
            end

            api.on_built_in_types do |t|
              if t.name == "Query"
                t.field "time", "String"
              end
            end
          end

          type_names = ::GraphQL::Schema.from_definition(result).types.keys
          expect(type_names.grep(/\AQuery/)).to eq ["Query"]
        end

        it "can be overridden via `raw_sdl` to support ElasticGraph tests that require a custom `Query` type" do
          query_type_def = <<~EOS.strip
            type Query {
              foo: Int
            }
          EOS

          result = define_schema do |schema|
            schema.raw_sdl query_type_def
          end

          expect(type_def_from(result, "Query")).to eq(query_type_def)
        end
      end
    end
  end
end
