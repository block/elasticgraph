# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/schema"
require "elastic_graph/support/monotonic_clock"

module ElasticGraph
  class GraphQL
    RSpec.describe Schema, :ensure_no_orphaned_types do
      it "can be instantiated with directives that have custom scalar arguments" do
        define_schema do |schema|
          schema.scalar_type "_FieldSet" do |t|
            t.mapping type: "keyword"
            t.json_schema type: "string"
          end

          schema.object_type "Widget" do |t|
            t.directive "key", fields: "id"
            t.field "id", "ID!"
            t.index "widgets"
          end

          schema.raw_sdl <<~EOS
            directive @key(fields: _FieldSet!) on OBJECT | INTERFACE
          EOS
        end
      end

      describe "#type_named" do
        let(:schema) do
          define_schema do |s|
            s.object_type "Color"
          end
        end

        it "finds a type by string name" do
          expect(schema.type_named("Color")).to be_a GraphQL::Schema::Type
        end

        it "finds a type by symbol name" do
          expect(schema.type_named(:Color)).to be_a GraphQL::Schema::Type
        end

        it "consistently returns the same type object" do
          color1 = schema.type_named("Color")
          color2 = schema.type_named("Color")
          color3 = schema.type_named(:Color)
          query = schema.type_named("Query")

          expect(color2).to be(color1)
          expect(color3).to be(color1)
          expect(query).not_to eq(color1)
        end

        it "raises an error when a type is misspelled (suggesting the correct spelling)" do
          expect {
            schema.type_named("Collor")
          }.to raise_error(Errors::NotFoundError, a_string_including("Collor", "Color"))
        end

        it "raises an error when a type cannot be found (or any suggestion)" do
          expect {
            schema.type_named("Person")
          }.to raise_error(Errors::NotFoundError, a_string_including("Person"))
        end
      end

      describe "#defined_types" do
        # Note: `defined_type` isn't used internally by ElasticGraph itself, but it's exposed for use by extensions.
        it "returns a list containing all explicitly defined types (excluding built-ins)" do
          schema = define_schema do |s|
            s.enum_type "Options" do |t|
              t.value "firstOption"
            end
            s.object_type "Color"
          end

          expect(schema.defined_types).to all be_a Schema::Type
          expect(schema.defined_types.map(&:name)).to include(:Options, :Color, :Query)
            .and exclude(:Int, :Float, :Boolean, :String, :ID)
        end
      end

      describe "#indexed_document_types" do
        it "returns a list containing all types defined as indexed types" do
          schema = define_schema do |s|
            define_indexed_type(s, "Person", "people")
            define_indexed_type(s, "Widget", "widgets")
            s.object_type "Options"
          end

          expect(schema.indexed_document_types).to contain_exactly(
            schema.type_named(:Person),
            schema.type_named(:Widget)
          )
        end
      end

      describe "#document_type_stored_in" do
        it "returns the type stored in the named index" do
          schema = schema_with_indices("Person" => "people", "Widget" => "widgets")

          expect(schema.document_type_stored_in("people")).to eq(schema.type_named(:Person))
          expect(schema.document_type_stored_in("widgets")).to eq(schema.type_named(:Widget))
        end

        it "raises an exception if given an unrecognizd index name" do
          schema = schema_with_indices("Person" => "people", "Widget" => "widgets")

          expect {
            schema.document_type_stored_in("foobars")
          }.to raise_error(Errors::NotFoundError, a_string_including("foobars"))
        end

        it "raises a clear exception if given the name of a rollover index instead of the source index definition name" do
          schema = schema_with_indices("Person" => "people", "Widget" => "widgets")

          expect {
            schema.document_type_stored_in("widgets#{ROLLOVER_INDEX_INFIX_MARKER}2021-02")
          }.to raise_error(ArgumentError, a_string_including("widgets#{ROLLOVER_INDEX_INFIX_MARKER}2021-02", "name of a rollover index"))
        end

        it "raises an exception if two GraphQL types are configured to use the same index" do
          schema = schema_with_indices("Person" => "widgets", "Widget" => "widgets")

          expect {
            schema.document_type_stored_in("widgets")
          }.to raise_error(Errors::SchemaError, a_string_including("widgets", "Person", "Widget"))
        end

        def schema_with_indices(index_name_by_type)
          define_schema do |s|
            define_indexed_type(s, "Person", index_name_by_type.fetch("Person"))
            define_indexed_type(s, "Widget", index_name_by_type.fetch("Widget"))

            s.object_type "Options" do
            end
          end
        end
      end

      describe "#enum_value_named" do
        let(:schema) do
          define_schema do |s|
            s.enum_type "ColorSpace" do |t|
              t.values "rgb", "srgb"
            end
          end
        end

        it "finds an enum_value when given a type and enum_value name strings" do
          expect(schema.enum_value_named("ColorSpace", "rgb")).to be_a GraphQL::Schema::EnumValue
        end

        it "finds an enum_value when given a type and enum_value name symbols" do
          expect(schema.enum_value_named(:ColorSpace, :rgb)).to be_a GraphQL::Schema::EnumValue
        end

        it "consistently returns the same enum_value_object" do
          enum_value1 = schema.enum_value_named(:ColorSpace, :rgb)
          enum_value2 = schema.enum_value_named(:ColorSpace, :rgb)
          enum_value3 = schema.enum_value_named("ColorSpace", "rgb")
          other_field = schema.enum_value_named(:ColorSpace, :srgb)

          expect(enum_value2).to be(enum_value1)
          expect(enum_value3).to be(enum_value1)
          expect(other_field).not_to eq(enum_value1)
        end

        it "raises an error when the type cannot be found" do
          expect {
            schema.enum_value_named(:ColorType, :name)
          }.to raise_error(Errors::NotFoundError, /ColorSpace/)
        end

        it "raises an error when the enum value cannot be found, suggesting a correction if it can find one" do
          expect {
            schema.enum_value_named(:ColorSpace, :srg)
          }.to raise_error(Errors::NotFoundError, a_string_including("ColorSpace", "srg", "Possible alternatives", "srgb"))
        end

        it "raises an error when the enum value cannot be found, with no suggestions if not close to any enum value name" do
          expect {
            schema.enum_value_named(:ColorSpace, :foo)
          }.to raise_error(Errors::NotFoundError, a_string_including("ColorSpace", "foo").and(excluding("Possible alternatives")))
        end
      end

      describe "#field_named" do
        {"" => "return type", "FilterInput" => "input type"}.each do |suffix, type_description|
          context "on a #{type_description}" do
            let(:schema) do
              define_schema do |s|
                s.object_type "Color" do |t|
                  t.field "red", "Int!"
                  t.field "green", "Int!"
                  t.field "blue", "Int!"
                end
              end
            end

            it "finds a field when given type and field name strings" do
              expect(field_named("Color", "blue")).to be_a GraphQL::Schema::Field
            end

            it "finds a field when given type and field name symbols" do
              expect(field_named(:Color, :blue)).to be_a GraphQL::Schema::Field
            end

            it "consistently returns the same field object" do
              field1 = field_named(:Color, :red)
              field2 = field_named(:Color, :red)
              field3 = field_named("Color", "red")
              other_field = field_named(:Color, :blue)

              expect(field2).to be(field1)
              expect(field3).to be(field1)
              expect(other_field).not_to eq(field1)
            end

            it "raises an error when the type part of the given field name cannot be found" do
              expect {
                field_named(:Person, :name)
              }.to raise_error(Errors::NotFoundError, /Person/)
            end

            it "raises an error when the field part of the given field name cannot be found, suggesting a correction if possible" do
              expect {
                field_named(:Color, :gren)
              }.to raise_error(Errors::NotFoundError, a_string_including("Color", "gren", "Possible alternatives", "green"))
            end

            it "raises an error when the field part of the given field name cannot be found, with no suggestions if not close to any field names" do
              expect {
                field_named(:Color, :purple)
              }.to raise_error(Errors::NotFoundError, a_string_including("Color", "purple").and(excluding("Possible alternatives")))
            end

            define_method :field_named do |type_name_root, field|
              schema.field_named("#{type_name_root}#{suffix}", field)
            end
          end
        end
      end

      it "inspects nicely" do
        schema = define_schema do |s|
          define_indexed_type(s, "Component", "components")
          define_indexed_type(s, "Address", "addresses")
        end

        expect(schema.inspect).to eq schema.to_s
        expect(schema.to_s).to eq "#<ElasticGraph::GraphQL::Schema 0x#{schema.__id__.to_s(16)} indexed_document_types=[Address, Component]>"
      end

      def define_schema(&schema_definition)
        build_graphql(schema_definition: schema_definition).schema
      end

      def define_indexed_type(schema, indexed_type, index_name, **index_options)
        schema.object_type indexed_type do |t|
          t.field "id", "ID!"
          t.index index_name, **index_options
        end
      end
    end
  end
end
