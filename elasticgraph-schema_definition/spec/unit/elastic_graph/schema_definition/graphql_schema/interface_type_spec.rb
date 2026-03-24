# Copyright 2024 - 2026 Block, Inc.
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
    RSpec.describe "GraphQL schema generation", "#interface_type" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "acts like `object_type` but defines a GraphQL `interface` instead of a GraphQL `type`" do
          result = define_schema do |schema|
            schema.interface_type "Named" do |t|
              t.documentation "A type that has a name."
              t.field "name", "String" do |f|
                f.documentation "The name of the object."
              end
            end
          end

          expect(type_def_from(result, "Named", include_docs: true)).to eq(<<~EOS.strip)
            """
            A type that has a name.
            """
            interface Named {
              """
              The name of the object.
              """
              name: String
            }
          EOS
        end

        it "raises a clear error if some subtypes are indexed and others are not" do
          expect {
            define_schema do |api|
              api.object_type("Person") do |t|
                t.field "id", "ID"
                t.field "name", "String"
                t.implements "Inventor"
                t.index "people"
              end

              api.object_type("Company") do |t|
                t.field "name", "String"
                t.implements "Inventor"
              end

              api.interface_type "Inventor" do |t|
                t.field "name", "String"
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("Inventor", "root document type")
        end

        it "respects a configured type name override" do
          result = define_schema(type_name_overrides: {"Named" => "Nameable"}) do |schema|
            schema.interface_type "Named" do |t|
              t.field "name", "String"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.implements "Named"
              t.index "widgets"
            end
          end

          expect(type_def_from(result, "Named")).to eq nil
          expect(type_def_from(result, "Nameable")).to eq(<<~EOS.strip)
            interface Nameable {
              name: String
            }
          EOS
          expect(type_def_from(result, "Widget")).to eq(<<~EOS.strip)
            type Widget implements Nameable {
              id: ID
              name: String
            }
          EOS

          expect(type_def_from(result, "NameableFilterInput")).not_to eq nil
          expect(type_def_from(result, "NameableConnection")).not_to eq nil
          expect(type_def_from(result, "NameableEdge")).not_to eq nil

          # Verify that there are _no_ `Named` types defined
          expect(result.lines.grep(/Named/)).to be_empty
        end

        %w[not all_of any_of any_satisfy].each do |field_name|
          it "produces a clear error if a `#{field_name}` field is defined since that will conflict with the filtering operators" do
            expect {
              define_schema do |schema|
                schema.interface_type "WidgetOptions" do |t|
                  t.field schema_elements.public_send(field_name), "String"
                end
              end
            }.to raise_error Errors::SchemaError, a_string_including("WidgetOptions.#{schema_elements.public_send(field_name)}", "reserved")
          end
        end

        it "raises a clear error when interfaces recursively implement each other" do
          expect {
            define_schema do |schema|
              schema.interface_type "A" do |t|
                t.implements "B"
                t.field "id", "ID!"
              end

              schema.interface_type "B" do |t|
                t.implements "A"
                t.field "id", "ID!"
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("A", "B", "circular reference chain")
        end

        it "allows interfaces to share a supertype without treating it as a cycle" do
          expect {
            define_schema do |schema|
              schema.interface_type "A" do |t|
                t.implements "B", "C"
                t.field "id", "ID!"
              end

              schema.interface_type "B" do |t|
                t.implements "D"
                t.field "id", "ID!"
              end

              schema.interface_type "C" do |t|
                t.implements "D"
                t.field "id", "ID!"
              end

              schema.interface_type "D" do |t|
                t.field "id", "ID!"
              end
            end
          }.not_to raise_error
        end

        describe "#implements" do
          include_examples "#implements",
            graphql_definition_keyword: "interface",
            ruby_definition_method: :interface_type

          context "SDL round-trip through GraphQL::Schema" do
            it "preserves Edge node fields for all interfaces in deep hierarchy" do
              # Uses specific alphabetical ordering to test that our SDL generation works around the GraphQL gem's
              # sensitivity to type name ordering. For context, see:
              # https://github.com/rmosolgo/graphql-ruby/issues/5580
              intermediate_sdl = define_schema do |api|
                api.interface_type "Alpha" do |t|
                  t.field "id", "ID!"
                end

                api.interface_type "Bravo" do |t|
                  t.implements "Alpha"
                  t.field "id", "ID!"
                end

                api.interface_type "Delta" do |t|
                  t.implements "Bravo"
                  t.field "id", "ID!"
                end

                api.interface_type "Echo" do |t|
                  t.implements "Delta"
                  t.field "id", "ID!"
                end

                api.object_type "Charlie" do |t|
                  t.implements "Echo"
                  t.field "id", "ID!"
                  t.index "charlies"
                end
              end

              round_tripped_sdl = ::GraphQL::Schema.from_definition(intermediate_sdl).to_definition

              expect(edge_type_from(round_tripped_sdl, "Charlie")).to include("node: Charlie")
              expect(edge_type_from(round_tripped_sdl, "Echo")).to include("node: Echo")
              expect(edge_type_from(round_tripped_sdl, "Delta")).to include("node: Delta")
              expect(edge_type_from(round_tripped_sdl, "Bravo")).to include("node: Bravo")
              expect(edge_type_from(round_tripped_sdl, "Alpha")).to include("node: Alpha")
            end
          end
        end
      end
    end
  end
end
