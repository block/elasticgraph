# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/json_ingestion/schema_definition/indexing/field"
require "elastic_graph/json_ingestion/schema_definition/indexing/field_reference"
require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/object"
require "elastic_graph/spec_support/schema_definition_helpers"
require "support/json_schema_matcher"

module ElasticGraph
  module JSONIngestion::SchemaDefinition
    ::RSpec.describe "JSON schema indexing wrappers" do
      include_context "SchemaDefinitionHelpers"

      # `FieldReference#resolve` is a lazy reference: the referenced type need not exist when a field is
      # defined, only when artifacts are dumped. These two specs drive both outcomes (resolves / never
      # resolves) through the public schema-definition API.
      describe "lazy field resolution" do
        it "resolves a field whose type is defined after the referencing type" do
          json_schema = dump_schema do |s|
            s.object_type "MyType" do |t|
              t.field "id", "ID!"
              t.field "other", "OtherType"
            end

            s.object_type "OtherType" do |t|
              t.field "name", "String"
            end
          end

          expect(json_schema).to have_json_schema_like("MyType", {
            "type" => "object",
            "properties" => {
              "id" => json_schema_ref("ID!"),
              "other" => json_schema_ref("OtherType")
            },
            "required" => %w[id other]
          })
        end

        it "raises a clear error (rather than blowing up internally) for a field whose type never resolves" do
          # When a field references a type that is never defined, the wrapped `FieldReference#resolve`
          # returns `nil`. The schema definition machinery relies on that `nil` to detect the unresolvable
          # type and surface a helpful error instead of crashing.
          expect {
            dump_schema do |s|
              s.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "mystery", "DoesNotExist"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("Type `DoesNotExist` cannot be resolved", "misspelled"))
        end
      end

      # Each wrapper is a value object that augments a wrapped schema-definition object with JSON schema
      # state. Their `==`/`eql?`/`hash` implementations exist so the schema-definition machinery can treat
      # two wrappers of equal state as interchangeable (e.g. for `Set`/`Hash`/`uniq` de-duplication) and
      # treat a wrapper as equal to the object it wraps. No public-API path depends on the *outcome* of
      # these comparisons today, so we exercise them directly — but on wrappers obtained from a schema
      # defined via the public API (converting the same schema element twice to obtain equal-but-distinct
      # wrappers), so they're used in context rather than fabricated with internal collaborators.
      describe "value semantics" do
        it "treats `FieldReference`s derived from the same field as interchangeable, and distinguishes other fields" do
          schema_field = widget_indexing_field("name")
          reference = schema_field.to_indexing_field_reference
          equivalent_reference = schema_field.to_indexing_field_reference
          other_reference = widget_indexing_field("id").to_indexing_field_reference

          expect_equivalent(reference, equivalent_reference)
          expect_distinct(reference, other_reference)
          expect_equal_to_wrapped(reference)
        end

        it "treats `Field`s derived from the same field as interchangeable, and distinguishes other fields" do
          field = widget_indexing_object_field_type.subfields.fetch(0)
          equivalent_field = widget_indexing_object_field_type.subfields.fetch(0)
          other_field = widget_indexing_object_field_type.subfields.fetch(1)

          expect_equivalent(field, equivalent_field)
          expect_distinct(field, other_field)
          expect_equal_to_wrapped(field)
        end

        it "treats `FieldType::Object`s derived from the same type as interchangeable, and distinguishes other types" do
          object_field_type = indexing_object_field_type_for("Widget")
          equivalent_object_field_type = indexing_object_field_type_for("Widget")
          other_object_field_type = indexing_object_field_type_for("Gadget")

          expect_equivalent(object_field_type, equivalent_object_field_type)
          expect_distinct(object_field_type, other_object_field_type)
          expect_equal_to_wrapped(object_field_type)
        end

        # The stateless leaf field-type wrappers (`Scalar`, `Enum`, `Union`) share their value semantics
        # via `FieldType::ValueSemantics`. They carry no JSON schema state of their own, so equality is
        # purely a function of the wrapped field type: two wrappers around equal field types are equal and
        # a wrapper equals the field type it wraps. We cover all three kinds since each must `prepend`
        # the shared module and nothing else (compiler or type checker) catches an omission.
        {"scalar" => "enum", "enum" => "union", "union" => "scalar"}.each do |leaf_kind, other_leaf_kind|
          it "treats `#{leaf_kind}` field-type wrappers as interchangeable when they wrap equal field types" do
            field_type = indexing_leaf_field_type(leaf_kind)
            equivalent_field_type = indexing_leaf_field_type(leaf_kind)
            other_field_type = indexing_leaf_field_type(other_leaf_kind)

            expect_equivalent(field_type, equivalent_field_type)
            expect_distinct(field_type, other_field_type)
            expect_equal_to_wrapped(field_type)
          end
        end

        # The assertions below compare the boolean result of `==`/`eql?` rather than passing the wrappers
        # to the `eq`/`eql` matchers directly. These wrappers delegate to the deep, cross-referential
        # schema-definition object graph, and on failure RSpec's differ would `pretty_print` both sides --
        # which balloons to tens of megabytes and takes seconds. Asserting on booleans keeps a failure
        # cheap to render (`expected true, got false`) regardless of how the comparison turns out.

        # Asserts the full value-object contract: equal-by-`==`, equal-by-`eql?`, equal `hash`, and -- the
        # behavior the contract exists for -- interchangeable as `Set`/`Hash` members.
        def expect_equivalent(wrapper, equivalent_wrapper)
          expect(wrapper == equivalent_wrapper).to be(true)
          expect(wrapper.eql?(equivalent_wrapper)).to be(true)
          expect(wrapper.hash).to eq(equivalent_wrapper.hash)
          expect(::Set.new([wrapper, equivalent_wrapper]).size).to eq(1)
        end

        def expect_distinct(wrapper, other_wrapper)
          expect(wrapper == other_wrapper).to be(false)
        end

        def expect_equal_to_wrapped(wrapper)
          expect(wrapper == wrapper.__getobj__).to be(true)
        end

        def widget_indexing_field(name)
          object_types_by_name.fetch("Widget").indexing_fields_by_name_in_index.fetch(name)
        end

        def widget_indexing_object_field_type
          indexing_object_field_type_for("Widget")
        end

        def indexing_object_field_type_for(type_name)
          object_types_by_name.fetch(type_name).to_indexing_field_type
        end

        # The `Widget` field whose indexing field type is the requested leaf kind. A different kind's field
        # gives an "other" leaf wrapper for inequality assertions.
        def indexing_leaf_field_type(leaf_kind)
          field_name = {"scalar" => "name", "enum" => "color", "union" => "thing"}.fetch(leaf_kind)
          subfield = widget_indexing_object_field_type.subfields.find { |f| f.name == field_name }
          subfield.indexing_field_type
        end

        def object_types_by_name
          @object_types_by_name ||= define_schema(schema_element_name_form: "snake_case") do |s|
            s.enum_type "Color" do |t|
              t.values "RED", "BLUE"
            end

            s.object_type "Square" do |t|
              t.field "side", "Int!"
            end

            s.object_type "Circle" do |t|
              t.field "radius", "Int!"
            end

            s.union_type "Shape" do |t|
              t.subtypes "Square", "Circle"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String" do |f|
                f.json_schema minLength: 1
              end
              t.field "color", "Color"
              t.field "thing", "Shape"
            end

            s.object_type "Gadget" do |t|
              t.field "id", "ID!"
              t.field "size", "Int"
            end
          end.state.object_types_by_name
        end
      end

      def dump_schema(&schema_definition)
        define_schema(schema_element_name_form: "snake_case", &schema_definition).current_public_json_schema
      end

      def json_schema_ref(type, is_keyword_type: %w[ID! ID String! String].include?(type))
        if type.end_with?("!")
          basic_json_schema_ref = {"$ref" => "#/$defs/#{type.delete_suffix("!")}"}

          if is_keyword_type
            {
              "allOf" => [
                basic_json_schema_ref,
                {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH}
              ]
            }
          else
            basic_json_schema_ref
          end
        else
          {
            "anyOf" => [
              json_schema_ref("#{type}!", is_keyword_type: is_keyword_type),
              {"type" => "null"}
            ]
          }
        end
      end
    end
  end
end
