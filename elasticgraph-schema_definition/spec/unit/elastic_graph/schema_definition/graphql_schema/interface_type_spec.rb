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
          }.to raise_error Errors::SchemaError, a_string_including("Inventor", "indexed")
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

        it "allows factory extensions to call new_interface_type without requiring an outer block" do
          # This tests that the factory method properly checks `block_given?` before yielding.
          # This is important for extension libraries that override factory methods.
          factory_extension = Module.new do
            define_method :new_interface_type do |name, &block|
              super(name) do |t|
                t.field "name", "String"
                # If a block was provided by the caller, call it
                block&.call(t)
              end
            end
          end

          api_extension = Module.new do
            define_singleton_method :extended do |api|
              api.factory.extend factory_extension
            end
          end

          result = define_schema(extension_modules: [api_extension]) do |api|
            # Call new_interface_type without a block - this would fail without `if block_given?`
            interface_type = api.factory.new_interface_type("Named")
            api.state.register_object_interface_or_union_type(interface_type)
          end

          expect(type_def_from(result, "Named")).to eq(<<~EOS.strip)
            interface Named {
              name: String
            }
          EOS
        end

        describe "#implements" do
          include_examples "#implements",
            graphql_definition_keyword: "interface",
            ruby_definition_method: :interface_type
        end
      end
    end
  end
end
