# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      ExampleElementNames = SchemaElementNamesDefinition.new(
        :foo, :multi_word_snake, :multiWordCamel
      )

      RSpec.describe SchemaElementNamesDefinition do
        it "exposes the set of element names via an `ELEMENT_NAMES` constant" do
          expect(ExampleElementNames::ELEMENT_NAMES).to eq [:foo, :multi_word_snake, :multiWordCamel]
        end

        it "exposes camelCase element names when so configured, via snake case attributes" do
          names = new_with(form: :camelCase)

          expect(names).to have_attributes(
            foo: "foo",
            multi_word_snake: "multiWordSnake",
            multi_word_camel: "multiWordCamel"
          )
        end

        it "exposes snake_case element names when so configured, via snake case attributes" do
          names = new_with(form: :snake_case)

          expect(names).to have_attributes(
            foo: "foo",
            multi_word_snake: "multi_word_snake",
            multi_word_camel: "multi_word_camel"
          )
        end

        it "exposes a `normalize_case` method that converts to snake_case when so configured" do
          names = new_with(form: :snake_case)

          expect(names.normalize_case("foo_bar")).to eq "foo_bar"
          expect(names.normalize_case("fooBar")).to eq "foo_bar"
          expect(names.normalize_case("FooBar")).to eq "_foo_bar"
        end

        it "exposes a `normalize_case` method that converts to camelCase when so configured" do
          names = new_with(form: :camelCase)

          expect(names.normalize_case("foo_bar")).to eq "fooBar"
          expect(names.normalize_case("fooBar")).to eq "fooBar"
          expect(names.normalize_case("FooBar")).to eq "FooBar"
        end

        it "allows overrides" do
          names = new_with(form: :camelCase, overrides: {foo: :bar})

          expect(names).to have_attributes(
            foo: "bar",
            multi_word_snake: "multiWordSnake",
            multi_word_camel: "multiWordCamel"
          )
        end

        it "allows instantiation args to be passed as strings since that is how it is loaded from YAML config" do
          names = new_with(form: "camelCase", overrides: {"foo" => "bar"})

          expect(names).to have_attributes(
            foo: "bar",
            multi_word_snake: "multiWordSnake",
            multi_word_camel: "multiWordCamel"
          )
        end

        it "raises a clear error when given an invalid `form` option" do
          expect {
            new_with(form: "kebab-case")
          }.to raise_error(Errors::SchemaError, /kebab-case/)
        end

        it "raises a clear error when given an unused override" do
          expect {
            new_with(overrides: {goo: :bar})
          }.to raise_error(Errors::SchemaError, a_string_including("overrides", "goo"))
        end

        it "raises a normal `NoMethodError` when accessing an undefined element name is attempted" do
          names = new_with(form: :camelCase)

          expect {
            names.not_a_method
          }.to raise_error(NoMethodError, /not_a_method/)
        end

        it "raises an error if two canonical names resolve to the same exposed name" do
          expect {
            new_with(overrides: {"foo" => "bar", "multi_word_snake" => "bar"})
          }.to raise_error(Errors::SchemaError, a_string_including("bar", "foo", "multi_word_snake"))
        end

        it "inspects nicely" do
          names = new_with(form: :camelCase, overrides: {foo: :bar})

          expect(names.inspect).to eq inspect_output_of("#<ElasticGraph::SchemaArtifacts::RuntimeMetadata::ExampleElementNames form=camelCase, overrides={foo: :bar}>")
          expect(names.to_s).to eq names.inspect
        end

        describe "#canonical_name_for" do
          let(:names) { new_with(form: "camelCase", overrides: {"foo" => "bar"}) }

          it "returns the canonical name for a given exposed name" do
            expect(names.canonical_name_for("bar")).to eq :foo
            expect(names.canonical_name_for("multiWordSnake")).to eq :multi_word_snake
            expect(names.canonical_name_for("multiWordCamel")).to eq :multiWordCamel
          end

          it "accepts either a string or symbol as an argument" do
            expect(names.canonical_name_for("bar")).to eq :foo
            expect(names.canonical_name_for(:bar)).to eq :foo
          end

          it "returns `nil` if there is no canonical name for the given exposed name" do
            expect(names.canonical_name_for("not_a_name")).to be nil
          end
        end

        def new_with(form: :camelCase, overrides: {})
          ExampleElementNames.new(form: form, overrides: overrides)
        end
      end
    end
  end
end
