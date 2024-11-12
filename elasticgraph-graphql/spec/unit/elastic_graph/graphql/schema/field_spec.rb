# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/schema/field"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    class Schema
      RSpec.describe Field, :ensure_no_orphaned_types do
        it "exposes the name as a lowercase symbol" do
          field = define_schema do |schema|
            schema.object_type "Color" do |t|
              t.field "red", "Int!"
            end
          end.field_named(:Color, :red)

          expect(field.name).to eq :red
        end

        it "exposes the parent type" do
          schema = define_schema do |s|
            s.object_type "Color" do |t|
              t.field "red", "Int!"
            end
          end

          field = schema.field_named(:Color, :red)
          expect(field.parent_type).to be schema.type_named(:Color)
        end

        it "inspects well" do
          field = define_schema do |schema|
            schema.object_type "Color" do |t|
              t.field "red", "Int!"
            end
          end.field_named(:Color, :red)

          expect(field.inspect).to eq "#<ElasticGraph::GraphQL::Schema::Field Color.red>"
        end

        describe "#type" do
          it "returns the type of the field" do
            schema = define_schema do |s|
              s.object_type "Color" do |t|
                t.field "red", "Int"
              end
            end

            field = schema.field_named(:Color, :red)

            expect(field.type.name).to eq :Int
            expect(field.type).to be schema.type_named(:Int)
          end

          it "supports wrapped types" do
            schema = define_schema do |s|
              s.object_type "Color" do |t|
                t.field "red", "[Int!]!"
              end
            end

            field = schema.field_named(:Color, :red)

            expect(field.type.name).to eq :"[Int!]!"
          end
        end

        describe "#relation_join" do
          it "returns a memoized `RelationJoin` if the field is a relation" do
            field = define_schema do |s|
              s.object_type "Color" do |t|
                t.field "id", "ID!"
                t.field "photo_id", "ID"
                t.index "colors"
              end

              s.object_type "Photo" do |t|
                t.field "id", "ID!"
                t.relates_to_many "colors", "Color", via: "photo_id", dir: :in, singular: "color"
                t.index "photos"
              end
            end.field_named(:Photo, :colors)

            expect(field.relation_join).to be_a(RelationJoin).and be(field.relation_join)
          end

          it "returns (and memoizes) nil if the field is not a relation" do
            allow(RelationJoin).to receive(:from).and_call_original

            field = define_schema do |s|
              s.object_type "Color" do |t|
                t.field "red", "Int"
              end
            end.field_named(:Color, :red)

            expect(field.relation_join).to be(nil).and be(field.relation_join)
            expect(RelationJoin).to have_received(:from).once
          end
        end

        describe "#sort_clauses_for" do
          it "raises a clear error if called on a field that lacks an `order_by` argument" do
            field = define_schema do |s|
              s.object_type "Widget" do |t|
                t.field "count", "Int"
              end
            end.field_named(:Widget, :count)

            expect {
              field.sort_clauses_for(:enum_value)
            }.to raise_error Errors::SchemaError, a_string_including("order_by", "Widget.count")
          end

          let(:schema) do
            define_schema do |s|
              s.object_type "Photo" do |t|
                t.field "id", "ID!"
                t.field "pixel_count", "Int!"
                t.field "created_at_ms", "Int!"
                t.index "photos" do |i|
                  i.default_sort "created_at_ms", :asc
                end
              end
            end
          end

          it "returns a list of datastore sort clauses when passed an array" do
            field = schema.field_named(:Query, :photos)
            sort_clauses = field.sort_clauses_for([:pixel_count_DESC, :created_at_ms_DESC])

            expect(sort_clauses).to eq([
              {"pixel_count" => {"order" => "desc"}},
              {"created_at_ms" => {"order" => "desc"}}
            ])
          end

          it "returns a list of a single datastore sort clause when passed a scalar" do
            field = schema.field_named(:Query, :photos)
            sort_clauses = field.sort_clauses_for(:pixel_count_DESC)

            expect(sort_clauses).to eq([{"pixel_count" => {"order" => "desc"}}])
          end

          it "raises an error if a sort value is undefined" do
            field = schema.field_named(:Query, :photos)

            expect {
              field.sort_clauses_for(:bogus_DESC)
            }.to raise_error(Errors::NotFoundError, a_string_including("No enum value named bogus_DESC"))
          end

          it "raises an error if a sort enum value lacks `sort_field` in the runtime metadata" do
            schema = define_schema do |s|
              s.object_type "Photo" do |t|
                t.field "id", "ID!"
                t.index "photos"
              end

              s.raw_sdl <<~EOS
                enum PhotoSort {
                  invalid_photo_sort_DESC
                }

                type Query {
                  photos(order_by: [PhotoSort!]): [Photo!]!
                }
              EOS
            end

            field = schema.field_named(:Query, :photos)

            expect {
              field.sort_clauses_for(:invalid_photo_sort_DESC)
            }.to raise_error(Errors::SchemaError, a_string_including("sort_field", "invalid_photo_sort_DESC"))
          end

          it "returns an empty array when given nil or []" do
            field = schema.field_named(:Query, :photos)

            expect(field.sort_clauses_for(nil)).to eq []
            expect(field.sort_clauses_for([])).to eq []
          end
        end

        describe "#computation_detail" do
          it "returns the aggregation function from an aggregated values field" do
            field = define_schema do |s|
              s.object_type "Photo" do |t|
                t.field "id", "ID!"
                t.field "some_field", "Int"
                t.index "photos"
              end
            end.field_named(:IntAggregatedValues, :exact_sum)

            expect(field.computation_detail).to eq(
              SchemaArtifacts::RuntimeMetadata::ComputationDetail.new(
                function: :sum,
                empty_bucket_value: 0
              )
            )
          end
        end

        describe "#aggregated" do
          it "returns true if the field's type is `FloatAggregatedValues`" do
            field = field_of_type("FloatAggregatedValues")

            expect(field.aggregated?).to be true
          end

          it "returns true if the field's type is `FloatAggregatedValues!`" do
            field = field_of_type("FloatAggregatedValues!")

            expect(field.aggregated?).to be true
          end

          it "returns false if the field's type is a list of `FloatAggregatedValues" do
            field = field_of_type("[FloatAggregatedValues]")
            expect(field.aggregated?).to be false

            field = field_of_type("[FloatAggregatedValues!]")
            expect(field.aggregated?).to be false

            field = field_of_type("[FloatAggregatedValues]!")
            expect(field.aggregated?).to be false

            field = field_of_type("[FloatAggregatedValues!]!")
            expect(field.aggregated?).to be false
          end

          it "returns false if the field is another type" do
            field = field_of_type("Int")

            expect(field.aggregated?).to be false
          end

          def field_of_type(type_name)
            define_schema do |schema|
              schema.object_type "Photo" do |t|
                t.field "some_field", type_name, filterable: false, aggregatable: false, groupable: false
              end
            end.field_named(:Photo, :some_field)
          end
        end

        describe "#name_in_index" do
          let(:schema) do
            define_schema do |s|
              s.object_type "Person" do |t|
                t.field "first_name", "String"
                t.field "alt_name", "String", name_in_index: "name"
              end
            end
          end

          context "when a schema field is defined with a `name_in_index`" do
            it "returns the `name_in_index` value" do
              field = schema.field_named(:Person, :alt_name)

              expect(field.name_in_index).to eq(:name)
            end
          end

          context "when a schema field does not have a `name_in_index`" do
            it "returns the field name" do
              field = schema.field_named(:Person, :first_name)

              expect(field.name_in_index).to eq(:first_name)
            end
          end
        end

        describe "#args_to_schema_form" do
          let(:field) do
            define_schema do |s|
              s.raw_sdl <<~EOS
                input Nested {
                  fooBar_bazzDazz: Int
                  nested: Nested
                }

                type Query {
                  foo(camelCaseField: Int, maybe_set_to_null: String, nested: Nested): Int
                }
              EOS
            end.field_named(:Query, :foo)
          end

          it "converts an args hash from the keyword args style provided by graphql gem to their form in the schema" do
            schema_args = field.args_to_schema_form({
              camel_case_field: 3,
              nested: {foo_bar_bazz_dazz: 12, nested: {foo_bar_bazz_dazz: nil}}
            })

            expect(schema_args).to eq({
              "camelCaseField" => 3,
              "nested" => {"fooBar_bazzDazz" => 12, "nested" => {"fooBar_bazzDazz" => nil}}
            })
          end

          it "throws a clear error when it cannot find a matching argument definition" do
            expect {
              field.args_to_schema_form({some_other_field: 17})
            }.to raise_error Errors::SchemaError, a_string_including("foo", "some_other_field")
          end
        end

        describe "#index_field_names_for_resolution" do
          it "returns the field name for a scalar field" do
            fields = index_field_names_for(:field, "foo", "Int")

            expect(fields).to contain_exactly("foo")
          end

          it "returns the overridden field name for a scalar field with `name_in_index` set" do
            fields = index_field_names_for(:field, "foo", "Int", name_in_index: "bar")

            expect(fields).to contain_exactly("bar")
          end

          it "returns an empty list for an embedded object field, because we do not need any fields to resolve it (but subfields will be needed to resolve them)" do
            fields = index_field_names_for(:field, "options", "WidgetOptions!") do |schema|
              schema.object_type "WidgetOptions" do |t|
                t.field "size", "Int"
              end
            end

            expect(fields).to be_empty
          end

          it "returns the foreign key field for a relation with an outbound foreign key" do
            fields = index_field_names_for(:relates_to_one, "car", "Car", via: "car_id", dir: :out) do |schema|
              define_indexed_car_type_on(schema)
            end

            expect(fields).to contain_exactly("car_id")
          end

          it "also returns the `id` field for a self-referential relation with an outbound foreign key" do
            fields = index_field_names_for(:relates_to_many, "children_widgets", "Widget", via: "children_ids", dir: :out, singular: "child_widget")

            expect(fields).to contain_exactly("id", "children_ids")
          end

          it "returns the `id` field for a relation with an inbound foreign key" do
            fields = index_field_names_for(:relates_to_one, "car", "Car", via: "widget_id", dir: :in) do |schema|
              define_indexed_car_type_on(schema)
            end

            expect(fields).to contain_exactly("id")
          end

          it "also returns the foreign key field for a self-referential relation with an inbound foreign key" do
            fields = index_field_names_for(:relates_to_one, "parent_widget", "Widget", via: "parent_id", dir: :in)

            expect(fields).to contain_exactly("id", "parent_id")
          end

          it "understands the semantics of relay connection edges/nodes" do
            graphql = build_graphql(schema_definition: lambda do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.index "widgets"
              end
            end)

            schema = graphql.schema

            expect(schema.field_named(:WidgetConnection, :edges).index_field_names_for_resolution).to eq []
            expect(schema.field_named(:WidgetConnection, :page_info).index_field_names_for_resolution).to eq []
            expect(schema.field_named(:WidgetEdge, :node).index_field_names_for_resolution).to eq []
            expect(schema.field_named(:WidgetEdge, :cursor).index_field_names_for_resolution).to eq []
          end

          def index_field_names_for(field_method, field_name, field_type, **field_args)
            graphql = build_graphql(schema_definition: lambda do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.public_send(field_method, field_name, field_type, **field_args)
                t.index "widgets"
              end

              yield s if block_given?
            end)

            graphql.schema.field_named(:Widget, field_name).index_field_names_for_resolution
          end
        end

        describe "#hidden_from_queries?" do
          it "returns `false` on a field whose type that has no backing indexed types" do
            schema = define_schema do |s|
              s.object_type "Color" do |t|
                t.field "name", "String"
              end
            end

            field = schema.field_named("Color", "name")

            expect(field.hidden_from_queries?).to be false
          end

          it "returns `false` on a field whose type has all index definitions accessible from queries on its backing indexed types" do
            schema = define_schema(index_definitions: {
              "colors" => config_index_def_of(query_cluster: "main")
            }) do |s|
              s.object_type "Color" do |t|
                t.field "id", "ID!"
                t.index "colors"
              end
            end

            field = schema.field_named("Query", "colors")

            expect(field.hidden_from_queries?).to be false
          end

          it "returns `true` on a field whose type has all index definitions inaccessible from queries on its backing indexed types" do
            schema = define_schema(index_definitions: {
              "colors" => config_index_def_of(query_cluster: nil)
            }) do |s|
              s.object_type "Color" do |t|
                t.field "id", "ID!"
                t.index "colors"
              end
            end

            field = schema.field_named("Query", "colors")

            expect(field.hidden_from_queries?).to be true
          end

          it "returns `false` on a field whose type has a mixture of accessible and inaccessible index definitions on its backing indexed types" do
            schema = define_schema(index_definitions: {
              "colors" => config_index_def_of(query_cluster: nil),
              "sizes" => config_index_def_of(query_cluster: "main")
            }) do |s|
              s.object_type "Color" do |t|
                t.field "id", "ID!"
                t.index "colors"
              end

              s.object_type "Size" do |t|
                t.field "id", "ID!"
                t.index "sizes"
              end

              s.union_type "ColorOrSize" do |t|
                t.subtypes "Color", "Size"
              end
            end

            colors = schema.field_named("Query", "colors")
            sizes = schema.field_named("Query", "sizes")
            colors_or_sizes = schema.field_named("Query", "color_or_sizes")

            expect(colors.hidden_from_queries?).to be true
            expect(sizes.hidden_from_queries?).to be false
            expect(colors_or_sizes.hidden_from_queries?).to be false
          end
        end

        describe "#coerce_result" do
          it "echoes back most results as-is" do
            schema = define_schema do |s|
              s.object_type "Color" do |t|
                t.field "name", "String"
              end
            end

            field = schema.field_named("Color", "name")

            expect(field.coerce_result("red")).to eq "red"
          end

          context "when an enum value name has been overridden" do
            let(:schema) do
              define_schema(enum_value_overrides_by_type: {
                "DayOfWeek" => {
                  "MONDAY" => "LUNDI",
                  "TUESDAY" => "WEDNESDAY",
                  "WEDNESDAY" => "TUESDAY"
                }
              }) do |s|
                s.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "created_at", "DateTime"
                  t.field "created_at_day_of_week", "DayOfWeek"
                  t.index "widgets"
                end
              end
            end

            it "coerces to the overridden name for a field on a graphql-only return type since ElasticGraph internal logic uses the original name" do
              field = schema.field_named("DateTimeGroupedBy", "as_day_of_week")

              expect(field.coerce_result("MONDAY")).to eq "LUNDI"
            end

            it "leaves the result as-is for an indexed field, since the overridden names are validated at indexing time and the value should already be in overridden form" do
              field = schema.field_named("Widget", "created_at_day_of_week")

              expect(field.coerce_result("TUESDAY")).to eq "TUESDAY"
            end
          end
        end

        def define_indexed_car_type_on(schema)
          schema.object_type "Car" do |t|
            t.field "id", "ID!"
            t.field "widget_id", "ID"
            t.index "cars"
          end
        end

        def define_schema(index_definitions: nil, **options, &schema_def)
          build_graphql(schema_definition: schema_def, index_definitions: index_definitions, **options).schema
        end
      end
    end
  end
end
