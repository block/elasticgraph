# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/resolvable_value"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"

module ElasticGraph
  class GraphQL
    module Resolvers
      PersonFieldNames = SchemaArtifacts::RuntimeMetadata::SchemaElementNamesDefinition.new(
        :name, :first_name, :birth_date, :age,
        :favorite_quote, :favorite_quote2, :truncate_to,
        *SchemaArtifacts::RuntimeMetadata::SchemaElementNames::ELEMENT_NAMES
      )

      RSpec.describe ResolvableValue do
        attr_accessor :schema_artifacts_by_first_name

        before(:context) do
          self.schema_artifacts_by_first_name = ::Hash.new do |hash, first_name|
            hash[first_name] = generate_schema_artifacts do |schema|
              schema.raw_sdl <<~EOS
                type Person {
                  name(truncate_to: Int): String
                  last_name: String
                  age: Int
                  #{first_name}: String
                  birth_date: String
                  birthDate: String
                  favorite_quote(truncate_to: Int, foo_bar_bazz: Int): String
                  favorite_quote2(trunc_to: Int): String
                }

                type Query {
                  person: Person
                }
              EOS
            end
          end
        end

        shared_examples_for ResolvableValue do |person_class|
          describe "#resolve" do
            it "delegates to a method of the same name on the object" do
              value = resolve(name: "Kristin", field: :name)

              expect(value).to eq "Kristin"
            end

            it "coerces the field name to its canonical form before calling the method" do
              value = resolve(name_form: :camelCase, birth_date: "2001-03-01", field: :birthDate)

              expect(value).to eq "2001-03-01"
            end

            it "evaluates the block passed to `ResolvableValue.new` just like `Data.define` does" do
              value = resolve(name: "John Doe", field: :first_name)
              expect(value).to eq "John"

              value = resolve(name_form: :camelCase, name: "John Doe", field: :firstName)
              expect(value).to eq "John"
            end

            it "raises a clear error if the field being resolved was not defined in the schema element names" do
              expect {
                resolve(name: "John Doe", field: :last_name)
              }.to raise_error(Errors::SchemaError, /last_name/)
            end

            it "raises an error if the field name is not in the form defined by the schema elements" do
              expect {
                resolve(name_form: :snake_case, birth_date: "2001-03-01", field: :birthDate)
              }.to raise_error(Errors::SchemaError, /birthDate/)
            end

            it "raises a `NoMethodError` if the field being resolved is not a defined method" do
              expect {
                resolve(name: "John Doe", field: :age)
              }.to raise_error(NoMethodError, /age/)
            end

            it "passes query field arguments to the resolver method" do
              value = resolve(
                name: "John Does",
                quote: "To be, or not to be",
                field: :favorite_quote,
                args: {truncate_to: 5}
              )

              expect(value).to eq "To be"
            end

            it "coerces arguments to their canonical form before calling the resolver method" do
              value = resolve(
                overrides: {truncate_to: "trunc_to"},
                name: "John Does",
                quote: "To be, or not to be",
                field: :favorite_quote2,
                args: {trunc_to: 5}
              )

              expect(value).to eq "To be"
            end

            it "raises a clear error if an argument is provided that has no canonical form definition" do
              expect {
                resolve(
                  name: "John Does",
                  quote: "To be, or not to be",
                  field: :favorite_quote,
                  args: {truncate_to: 5, foo_bar_bazz: 23}
                )
              }.to raise_error Errors::SchemaError, a_string_including("foo_bar_bazz")
            end

            it "raises a clear error if arguments are provided to a resolver method that does not expect them" do
              expect {
                resolve(
                  name: "John Does",
                  quote: "To be, or not to be",
                  field: :name,
                  args: {truncate_to: 5}
                )
              }.to raise_error ArgumentError
            end

            def resolve(args: {}, **options)
              person, field = person_object_and_schema_field(**options)
              args = field.args_to_schema_form(args)
              lookahead = instance_double("GraphQL::Execution::Lookahead")
              person.resolve(field: field, object: person, context: {}, args: args, lookahead: lookahead)
            end
          end

          define_method :person_object_and_schema_field do |
            field:, name_form: :snake_case, overrides: {},
            name: "John", birth_date: "2002-09-01", quote: "To be, or not to be, that is the question."
          |
            element_names = PersonFieldNames.new(form: name_form, overrides: overrides)

            person = person_class.new(
              schema_element_names: element_names,
              name: name,
              quote: quote,
              birth_date: birth_date
            )

            [person, build_graphql(element_names).schema.field_named(:Person, field)]
          end

          def build_graphql(element_names)
            super(schema_artifacts: schema_artifacts_by_first_name[element_names.first_name])
          end
        end

        context "with a `ResolvableValue` with methods defined in a passed block" do
          block_person = ResolvableValue.new(:name, :birth_date, :quote) do
            def first_name
              name.split(" ").first
            end

            def favorite_quote(truncate_to:)
              quote[0...truncate_to]
            end

            def favorite_quote2(truncate_to:)
              quote[0...truncate_to]
            end
          end

          include_examples ResolvableValue, block_person
        end

        context "with a `ResolvableValue` with methods defined in a subclass" do
          subclass_person = ::Class.new(ResolvableValue.new(:name, :birth_date, :quote)) do
            def first_name
              name.split(" ").first
            end

            def favorite_quote(truncate_to:)
              quote[0...truncate_to]
            end

            def favorite_quote2(truncate_to:)
              quote[0...truncate_to]
            end
          end

          include_examples ResolvableValue, subclass_person
        end
      end
    end
  end
end
