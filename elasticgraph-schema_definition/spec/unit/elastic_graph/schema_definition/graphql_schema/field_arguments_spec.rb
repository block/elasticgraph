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
    RSpec.describe "GraphQL schema generation", "field arguments" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "allows field arguments to be defined with documentation and directives" do
          result = define_schema do |api|
            api.object_type "MyType" do |t|
              t.field "negate", "Int!" do |f|
                f.argument "x", "Int" do |a|
                  a.documentation "The value to negate."
                  a.directive "deprecated", reason: "This arg will stop being supported."
                end
              end
            end
          end

          expect(type_def_from(result, "MyType", include_docs: true)).to eq(<<~EOS.strip)
            type MyType {
              negate(
                """
                The value to negate.
                """
                x: Int @deprecated(reason: "This arg will stop being supported.")): Int!
            }
          EOS
        end

        it "allows field arguments to be defined with default values" do
          result = define_schema do |api|
            api.object_type "MyType" do |t|
              t.field "foo", "Int!" do |f|
                f.argument "no_default", "Int!"
                f.argument "default_of_null", "Int" do |a|
                  a.default nil
                end

                f.argument "default_of_3", "Int!" do |a|
                  a.default 3
                end

                f.argument "default_with_directive", "Int" do |a|
                  a.directive "deprecated", reason: "unused"
                  a.default 4
                end
              end
            end
          end

          expect(type_def_from(result, "MyType")).to eq(<<~EOS.strip)
            type MyType {
              foo(
                no_default: Int!
                default_of_null: Int = null
                default_of_3: Int! = 3
                default_with_directive: Int = 4 @deprecated(reason: "unused")): Int!
            }
          EOS
        end

        it "allows input fields to be defined with default values" do
          result = define_schema do |api|
            filter = api.factory.new_filter_input_type("InputWithDefaults") do |t|
              t.field "no_default", "Int!"
              t.field "default_of_null", "Int" do |f|
                f.default nil
              end

              t.field "default_of_3", "Int!" do |f|
                f.default 3
              end

              t.field "default_with_directive", "Int" do |f|
                f.directive "deprecated", reason: "unused"
                f.default 4
              end

              t.graphql_only true
            end

            api.state.register_input_type(filter)
          end

          expect(type_def_from(result, "InputWithDefaultsFilterInput")).to eq(<<~EOS.strip)
            input InputWithDefaultsFilterInput {
              #{schema_elements.any_of}: [InputWithDefaultsFilterInput!]
              not: InputWithDefaultsFilterInput
              no_default: Int!
              default_of_null: Int = null
              default_of_3: Int! = 3
              default_with_directive: Int = 4 @deprecated(reason: "unused")
            }
          EOS
        end

        it "does not offer the `.default` API on non-input fields (since it only makes sense on inputs)" do
          expect {
            define_schema do |api|
              api.object_type "MyType" do |t|
                t.field "default_of_null", "Int" do |f|
                  f.default nil
                end
              end
            end
          }.to raise_error NoMethodError, a_string_including("default", ElasticGraph::SchemaDefinition::SchemaElements::Field.name)
        end

        it "raises a clear error when a field argument name is not formatted correctly" do
          expect {
            define_schema do |api|
              api.object_type "MyType" do |t|
                t.field "foo", "Int!" do |f|
                  f.argument "invalid.name", "Int!"
                end
              end
            end
          }.to raise_invalid_graphql_name_error_for("invalid.name")
        end
      end
    end
  end
end
