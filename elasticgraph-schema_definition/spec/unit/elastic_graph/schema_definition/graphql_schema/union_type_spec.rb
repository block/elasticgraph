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
    RSpec.describe "GraphQL schema generation", "#union_type" do
      include_context "GraphQL schema spec support"

      with_both_casing_forms do
        it "can generate a union of a single type" do
          pre_def = ->(api) {
            api.object_type("Person") do |t|
              t.field "id", "ID"
            end
          }

          result = union_type "Inventor", pre_def: pre_def do |t|
            t.subtype "Person"
          end

          expect(result).to eq(<<~EOS)
            union Inventor = Person
          EOS
        end

        it "can generate a union of a multiple types" do
          pre_def = ->(api) {
            %w[Person Company].each do |name|
              api.object_type(name) do |t|
                t.field "id", "ID"
                # Verify `relates_to_many` doesn't cause problems -- originally, our field argument
                # implementation wrongly caused it to consider the same `relates_to_many` field on
                # both subtypes to be different when they were the same.
                t.relates_to_many "inventions", "Inventor", via: "inventor_id", dir: :in, singular: "invention"
                t.index name.downcase
              end
            end
          }

          result = union_type "Inventor", pre_def: pre_def do |t|
            t.subtype "Person"
            t.subtype "Company"
          end

          expect(result).to eq(<<~EOS)
            union Inventor = Person | Company
          EOS
        end

        it "allows many subtypes to be defined in one call for convenience" do
          pre_def = ->(api) {
            %w[Red Green Yellow Orange].each do |name|
              api.object_type(name) do |t|
                t.field "id", "ID"
              end
            end
          }

          result = union_type "Color", pre_def: pre_def do |e|
            # they can be individually listed
            e.subtypes "Red", "Green"
            # ...or passed as a single array
            e.subtypes %w[Yellow Orange]
          end

          expect(result).to eq(<<~EOS)
            union Color = Red | Green | Yellow | Orange
          EOS
        end

        it "can generate directives on the type" do
          pre_def = ->(api) {
            api.raw_sdl "directive @foo(size: Int = null) repeatable on UNION"

            %w[Red Green Blue].each do |name|
              api.object_type(name) do |t|
                t.field "id", "ID"
              end
            end
          }

          result = union_type "Color", pre_def: pre_def do |t|
            t.directive "foo", size: 1
            t.directive "foo", size: 3
            t.subtype "Red"
            t.subtype "Green"
            t.subtype "Blue"
          end

          expect(result).to eq(<<~EOS)
            union Color @foo(size: 1) @foo(size: 3) = Red | Green | Blue
          EOS
        end

        it "supports doc comments on the type" do
          pre_def = ->(api) {
            api.object_type("Person") do |t|
              t.field "id", "ID"
            end
          }

          result = union_type "Inventor", pre_def: pre_def do |t|
            t.documentation "A person who has invented something."
            t.subtype "Person"
          end

          expect(result).to eq(<<~EOS)
            """
            A person who has invented something.
            """
            union Inventor = Person
          EOS
        end

        it "respects configured type name overrides in both the supertype and subtype names" do
          result = define_schema(type_name_overrides: {"Thing" => "Entity", "Widget" => "Gadget"}) do |schema|
            schema.object_type "Component" do |t|
              t.field "id", "ID"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID"
            end

            schema.union_type "Thing" do |t|
              t.subtype "Component"
              t.subtype "Widget"
              t.index "things"
            end
          end

          expect(type_def_from(result, "Thing")).to eq nil
          expect(type_def_from(result, "Entity")).to eq("union Entity = Component | Gadget")

          expect(type_def_from(result, "EntityFilterInput")).not_to eq nil
          expect(type_def_from(result, "EntityConnection")).not_to eq nil
          expect(type_def_from(result, "EntityEdge")).not_to eq nil

          # Verify that there are _no_ `Thing` types defined
          expect(result.lines.grep(/Thing/)).to be_empty
        end

        it "raises a clear error when the union type name is invalid" do
          expect {
            define_schema do |api|
              api.object_type("Person") do |t|
                t.field "id", "ID"
              end

              api.union_type("Invalid.Name") {}
            end
          }.to raise_invalid_graphql_name_error_for("Invalid.Name")
        end

        it "raises a clear error when the same type union is defined multiple times" do
          expect {
            define_schema do |api|
              %w[Red Red2].each do |name|
                api.object_type name do |t|
                  t.field "id", "ID"
                end
              end

              api.union_type "Color" do |t|
                t.subtype "Red"
              end

              api.union_type "Color" do |t|
                t.subtype "Red2"
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("Duplicate", "Color")
        end

        it "raises a clear error when the same subtype is defined multiple times" do
          expect {
            define_schema do |api|
              %w[Red Green Blue].each do |name|
                api.object_type(name) do |t|
                  t.field "id", "ID"
                end
              end

              api.union_type "Color" do |t|
                t.subtype "Red"
                t.subtype "Green"
                t.subtype "Red"
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("Duplicate", "Union", "Red")
        end

        it "raises a clear error when no subtypes are defined" do
          expect {
            union_type "Color" do |e|
            end
          }.to raise_error Errors::SchemaError, a_string_including("Color", "has no subtypes")
        end

        it "raises a clear error if one of the subtypes is undefined" do
          expect {
            union_type "Inventor" do |t|
              t.subtype "Person"
            end
          }.to raise_error Errors::SchemaError, a_string_including("Person", "not a defined object type")
        end

        it "raises a clear error when the type name has the type wrapping characters" do
          expect {
            define_schema do |api|
              api.object_type("Person") do |t|
                t.field "id", "ID"
              end

              api.union_type "[InvalidName!]!" do |e|
                e.subtype "Person"
              end
            end
          }.to raise_invalid_graphql_name_error_for("[InvalidName!]!")
        end

        it "raises a clear error if one of the subtypes is an enum type" do
          expect {
            define_schema do |api|
              api.enum_type("Person") do |t|
                t.value "Bob"
              end

              api.union_type "Inventor" do |t|
                t.subtype "Person"
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("Person", "not a defined object type")
        end

        it "raises a clear error if some subtypes are indexed and others are not" do
          expect {
            define_schema do |api|
              api.object_type("Person") do |t|
                t.field "id", "ID"
                t.index "people"
              end

              api.object_type("Company") do |t|
              end

              api.union_type "Inventor" do |t|
                t.subtypes "Person", "Company"
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("Inventor", "indexed")
        end

        it "allows the same field on two subtypes to have different documentation" do
          result = define_schema do |api|
            api.object_type "Person" do |t|
              t.field "name", "String" do |f|
                f.documentation "The person's name."
              end
              t.field "nationality", "String"
            end

            api.object_type "Company" do |t|
              t.field "name", "String" do |f|
                f.documentation "The company's name."
              end
              t.field "stock_ticker", "String"
            end

            api.union_type "Inventor" do |t|
              t.subtypes "Person", "Company"
            end
          end

          expect(type_def_from(result, "Inventor")).to eq("union Inventor = Person | Company")
        end

        def union_type(name, *args, pre_def: nil, **options, &block)
          result = define_schema do |api|
            pre_def&.call(api)
            api.union_type(name, *args, **options, &block)
          end

          # We add a line break to match the expectations which use heredocs.
          type_def_from(result, name, include_docs: true) + "\n"
        end
      end
    end
  end
end
