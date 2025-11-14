# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/spec_support/have_readable_to_s_and_inspect_output"
require_relative "graphql_schema_spec_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "ElasticGraph.define_schema" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "evaluates the given block against the active API instance, allowing `ElasticGraph.define_schema` to be used many times" do
          api = API.new(schema_elements, true)

          api.as_active_instance do
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 1
              schema.object_type("Person") do |t|
                t.field "id", "ID"
              end
            end

            ElasticGraph.define_schema do |schema|
              schema.object_type("Place") do |t|
                t.field "id", "ID"
              end
            end
          end

          result = api.results.graphql_schema_string

          expect(type_def_from(result, "Person")).to eq(<<~EOS.strip)
            type Person {
              id: ID
            }
          EOS

          expect(type_def_from(result, "Place")).to eq(<<~EOS.strip)
            type Place {
              id: ID
            }
          EOS
        end

        it "raises a clear error when there is no active API instance" do
          expect {
            ElasticGraph.define_schema { |schema| }
          }.to raise_error Errors::SchemaError, a_string_including("Let ElasticGraph load")
        end

        it "does not leak the active API instance, even when an error occurs" do
          api = API.new(schema_elements, true)

          expect {
            api.as_active_instance do
              ElasticGraph.define_schema do |schema|
                raise "boom"
              end
            end
          }.to raise_error(/boom/)

          expect {
            ElasticGraph.define_schema { |schema| }
          }.to raise_error Errors::SchemaError, a_string_including("Let ElasticGraph load")
        end

        it "does not allow `user_defined_field_references_by_type_name` to be accessed on `state` before the schema definition is done" do
          expect {
            define_schema do |schema|
              schema.state.user_defined_field_references_by_type_name
            end
          }.to raise_error(
            Errors::SchemaError,
            "Cannot access `user_defined_field_references_by_type_name` until the schema definition is complete."
          )
        end

        it "produces the same GraphQL output, regardless of the order the types are defined in" do
          object_type_definitions = {
            "Component" => lambda do |t|
              t.field "id", "ID!"
              t.relates_to_one "widget", "Widget", via: "widget_id", dir: :out
              t.index "components"
            end,

            "Widget" => lambda do |t|
              t.field "id", "ID!"
              t.field "versions", "[WidgetVersion]" do |f|
                f.mapping type: "nested"
              end
              t.relates_to_many "components", "Component", via: "widget_id", dir: :in, singular: "component"
              t.index "widgets"
            end,

            "WidgetVersion" => lambda do |t|
              t.field "version", "Int!"
            end
          }

          all_definition_orderings = [
            # Note: when this spec was written, these first 2 orderings (where `Component` came first) caused infinite recursion.
            # At the time, having `Component` come first caused an issue because it caused `ComponentEdge` (with it's
            # `node: Component` field) and `ComponentConnection` (with its `nodes: [Component!]!` field) to be generated
            # before, `Widget.components` was processed, leading to additional field references to the `Component` type.
            %w[Component Widget WidgetVersion],
            %w[Component WidgetVersion Widget],
            # In contrast, these last 4 orderings did not cause that problem and always produced the same output.
            %w[Widget WidgetVersion Component],
            %w[Widget Component WidgetVersion],
            %w[WidgetVersion Widget Component],
            %w[WidgetVersion Component Widget]
          ]

          uniq_results_for_each_ordering = all_definition_orderings.map do |type_names_in_order|
            define_schema do |schema|
              type_names_in_order.each do |type_name|
                schema.object_type(type_name, &object_type_definitions.fetch(type_name))
              end
            end
          end.uniq

          expect(uniq_results_for_each_ordering.size).to eq 1

          # Also compare the first and last, so that if there are multiple we get a diff showing how they differ.
          expect(uniq_results_for_each_ordering.first).to eq uniq_results_for_each_ordering.last
        end

        it "returns reasonably-sized strings from `#inspect` and `#to_s` for all objects exposed to users so that the exception output if the user misspells a method name is readable" do
          define_schema do |schema|
            expect(schema).to have_readable_to_s_and_inspect_output

            schema.on_built_in_types do |t|
              expect(t).to have_readable_to_s_and_inspect_output
            end

            schema.scalar_type "MyScalar" do |t|
              expect(t).to have_readable_to_s_and_inspect_output.including("MyScalar")
              t.mapping type: "keyword"
              t.json_schema type: "string"
            end

            schema.enum_type "Color" do |t|
              expect(t).to have_readable_to_s_and_inspect_output.including("Color")
              t.value "RED" do |v|
                expect(v).to have_readable_to_s_and_inspect_output.including("RED")
              end
            end

            schema.interface_type "Identifiable" do |t|
              expect(t).to have_readable_to_s_and_inspect_output.including("Identifiable")

              t.field "id", "ID" do |f|
                expect(f).to have_readable_to_s_and_inspect_output.including("id: ID")
              end
            end

            schema.union_type "Entity" do |t|
              expect(t).to have_readable_to_s_and_inspect_output.including("Entity")
              t.subtype "Widget"
            end

            schema.object_type "Widget" do |t|
              expect(t).to have_readable_to_s_and_inspect_output.including("Widget")

              t.field "name", "String!" do |f|
                f.documentation "the field docs"
                expect(f).to have_readable_to_s_and_inspect_output.including("Widget.name: String!").and_excluding("the field docs")

                f.argument "int", "Int" do |a|
                  a.documentation "the arg docs"
                  expect(a).to have_readable_to_s_and_inspect_output.including("Widget.name(int: Int)").and_excluding("the arg docs")
                end

                f.customize_filter_field do |ff|
                  expect(ff).to have_readable_to_s_and_inspect_output
                end

                f.on_each_generated_schema_element do |se|
                  expect(se).to have_readable_to_s_and_inspect_output
                end
              end

              t.field "id", "ID!"

              t.index "widgets" do |i|
                expect(i).to have_readable_to_s_and_inspect_output.including("widgets")
              end
            end

            expect(schema.factory).to have_readable_to_s_and_inspect_output
            expect(schema.state).to have_readable_to_s_and_inspect_output
            expect(schema.results).to have_readable_to_s_and_inspect_output
          end
        end
      end
    end
  end
end
