# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/record_preparer"
require "elastic_graph/spec_support/schema_definition_helpers"
require "support/multiple_version_support"

module ElasticGraph
  class Indexer
    RSpec.describe RecordPreparer::Factory do
      include_context "MultipleVersionSupport"

      let(:factory_with_multiple_versions) do
        build_indexer_with_multiple_schema_versions(schema_versions: {
          1 => lambda do |schema|
            schema.object_type "MyType" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.index "my_type"
            end
          end,

          2 => lambda do |schema|
            schema.object_type "MyType" do |t|
              t.field "id", "ID!"
              t.field "name", "String!"
              t.index "my_type"
            end
          end
        }).record_preparer_factory
      end

      describe "#for_json_schema_version" do
        it "memoizes `RecordPreparer` since they are immutable and that saves on memory" do
          for_v1 = factory_with_multiple_versions.for_json_schema_version(1)
          for_v2 = factory_with_multiple_versions.for_json_schema_version(2)

          expect(for_v1).not_to eq(for_v2)
          expect(factory_with_multiple_versions.for_json_schema_version(1)).to be for_v1
        end
      end

      describe "#for_latest_json_schema_version" do
        it "returns the record preparer for the latest JSON schema version" do
          for_v2 = factory_with_multiple_versions.for_json_schema_version(2)

          expect(factory_with_multiple_versions.for_latest_json_schema_version).to be for_v2
        end
      end
    end

    RSpec.describe RecordPreparer do
      describe "#prepare_for_index" do
        it "tolerates a `nil` value where an object would usually be" do
          preparer = build_preparer do |s|
            s.enum_type "Color" do |t|
              t.value "BLUE"
              t.value "GREEN"
              t.value "RED"
            end

            s.object_type "WidgetOptions" do |t|
              t.field "color", "Color"
            end

            s.object_type "MyType" do |t|
              t.field "id", "ID!"
              t.field "options", "WidgetOptions"
              t.index "my_type"
            end
          end

          record = preparer.prepare_for_index("MyType", {"id" => "1", "options" => nil})

          expect(record).to eq({"id" => "1", "options" => nil})
        end

        it "leaves enum values unchanged (notable since enum types aren't recorded in runtime metadata `scalar_types_by_name`)" do
          preparer = build_preparer do |s|
            s.enum_type "Color" do |t|
              t.value "BLUE"
              t.value "GREEN"
              t.value "RED"
            end

            s.object_type "MyType" do |t|
              t.field "id", "ID!"
              t.field "color", "Color"
              t.index "my_type"
            end
          end

          record = preparer.prepare_for_index("MyType", {"id" => "1", "color" => "GREEN"})

          expect(record).to eq({"id" => "1", "color" => "GREEN"})
        end

        it "drops excess fields not defined in the schema" do
          preparer = build_preparer do |s|
            s.object_type "Position" do |t|
              t.field "x", "Float!"
              t.field "y", "Float!"
            end

            s.object_type "Component" do |t|
              t.field "created_at", "String!"
              t.field "id", "ID!"
              t.field "name", "String!"
              t.field "position", "Position!"
              t.index "components"
            end
          end

          record = {
            "id" => "1",
            "created_at" => "2019-06-01T12:00:00Z",
            "name" => "my_component",
            "extra_field1" => {
              "field1" => {
                "field2" => 3,
                "field3" => {
                  "field4" => 4
                },
                "field6" => "value"
              },
              "field7" => "5"
            },
            "extra_field2" => 2,
            "position" => {
              "x" => 1.1,
              "y" => 2.1,
              "extra_field1" => "value1",
              "extra_field2" => {
                "extra_field3" => 3
              }
            }
          }

          record = preparer.prepare_for_index("Component", record)

          expect(record).to eq({
            "id" => "1",
            "name" => "my_component",
            "created_at" => "2019-06-01T12:00:00Z",
            "position" => {
              "x" => 1.1,
              "y" => 2.1
            }
          })
        end

        it "ignores excess fields defined in the schema that are missing from the record" do
          preparer = build_preparer do |s|
            s.object_type "Position" do |t|
              t.field "x", "Float!"
              t.field "y", "Float!"
            end

            s.object_type "Component" do |t|
              t.field "created_at", "String!"
              t.field "id", "ID!"
              t.field "name", "String!"
              t.field "position", "Position!"
              t.index "components"
            end
          end

          record = {
            "id" => "1",
            "name" => "my_component",
            "position" => {
              "x" => 1.1
            }
          }

          record = preparer.prepare_for_index("Component", record)

          expect(record).to eq({
            "id" => "1",
            "name" => "my_component",
            "position" => {
              "x" => 1.1
            }
          })
        end

        it "handles abstract types (like type unions) stored in separate indexes, properly omitting `__typename`" do
          preparer = build_preparer do |s|
            s.object_type "TypeA" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.index "type_a"
            end

            s.object_type "TypeB" do |t|
              t.field "id", "ID!"
              t.field "size", "Int"
              t.index "type_b"
            end

            s.union_type "TypeAOrB" do |t|
              t.subtype "TypeA"
              t.subtype "TypeB"
            end
          end

          record = preparer.prepare_for_index("TypeB", {"id" => "1", "size" => 3, "__typename" => "TypeB"})

          expect(record).to eq({"id" => "1", "size" => 3})
        end

        it "handles abstract types (like type unions) stored in a single index, properly including `__typename`" do
          preparer = build_preparer do |s|
            s.object_type "TypeA" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
            end

            s.object_type "TypeB" do |t|
              t.field "id", "ID!"
              t.field "size", "Int"
            end

            s.union_type "TypeAOrB" do |t|
              t.subtype "TypeA"
              t.subtype "TypeB"
              t.index "type_a_or_b"
            end
          end

          record = preparer.prepare_for_index("TypeAOrB", {"id" => "1", "size" => 3, "__typename" => "TypeB"})

          expect(record).to eq({"id" => "1", "size" => 3, "__typename" => "TypeB"})
        end

        it "handles nested abstract types, properly including `__typename` on them" do
          preparer = build_preparer do |s|
            s.object_type "Person" do |t|
              t.field "name", "String"
              t.field "nationality", "String"
            end

            s.object_type "Company" do |t|
              t.field "name", "String"
              t.field "stock_ticker", "String"
            end

            s.union_type "Inventor" do |t|
              t.subtypes "Person", "Company"
            end

            s.object_type "Invention" do |t|
              t.field "id", "ID"
              t.field "inventor", "Inventor"
              t.index "inventions"
            end
          end

          record = preparer.prepare_for_index("Invention", {
            "id" => "1",
            "inventor" => {
              "name" => "Block",
              "stock_ticker" => "SQ",
              "__typename" => "Company"
            }
          })

          expect(record).to eq({
            "id" => "1",
            "inventor" => {
              "name" => "Block",
              "stock_ticker" => "SQ",
              "__typename" => "Company"
            }
          })
        end

        it "renames fields from the public name to the internal index field name when they differ" do
          preparer = build_preparer do |s|
            s.object_type "WidgetOptions" do |t|
              t.field "color", "String", name_in_index: "clr"
            end

            s.object_type "MyType" do |t|
              t.field "id", "ID!"
              t.field "options", "WidgetOptions"
              t.field "name", "String", name_in_index: "name2"
              t.index "my_type"
            end
          end

          record = preparer.prepare_for_index("MyType", {"id" => "1", "options" => {"color" => "RED"}, "name" => "Winston"})

          expect(record).to eq({"id" => "1", "options" => {"clr" => "RED"}, "name2" => "Winston"})
        end
      end

      context "when working with events for an old JSON schema version" do
        include_context "SchemaDefinitionHelpers"

        it "handles events for old versions before a field was deleted" do
          preparer = build_preparer_for_old_json_schema_version(
            v1_def: ->(schema) {
              schema.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.index "my_type"
              end
            },

            v2_def: ->(schema) {
              schema.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.deleted_field "name"
                t.index "my_type"
              end
            }
          )

          record = preparer.prepare_for_index("MyType", {"id" => "1", "name" => "Winston"})

          expect(record).to eq({"id" => "1"})
        end

        it "properly omits `__typename` under an embedded field for a non-abstract type, even when the type has been renamed" do
          preparer = build_preparer_for_old_json_schema_version(
            v1_def: ->(schema) {
              schema.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "cost", "Money"
                t.index "my_type"
              end

              schema.object_type "Money" do |t|
                t.field "amount", "Int"
              end
            },

            v2_def: ->(schema) {
              schema.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "cost", "Money2"
                t.index "my_type"
              end

              schema.object_type "Money2" do |t|
                t.field "amount", "Int"
                t.renamed_from "Money"
              end
            }
          )

          record = preparer.prepare_for_index("MyType", {"id" => "1", "cost" => {"amount" => 10, "__typename" => "Money"}})

          expect(record).to eq({"id" => "1", "cost" => {"amount" => 10}})
        end

        def build_preparer_for_old_json_schema_version(v1_def:, v2_def:)
          v1_results = define_schema do |schema|
            schema.json_schema_version 1
            v1_def.call(schema)
          end

          v2_results = define_schema do |schema|
            schema.json_schema_version 2
            v2_def.call(schema)
          end

          v1_merge_result = v2_results.merge_field_metadata_into_json_schema(v1_results.current_public_json_schema)

          expect(v1_merge_result.missing_fields).to be_empty
          expect(v1_merge_result.missing_types).to be_empty

          allow(v2_results).to receive(:json_schemas_for).with(1).and_return(v1_merge_result.json_schema)

          RecordPreparer::Factory.new(v2_results).for_json_schema_version(1)
        end

        def define_schema(&schema_definition)
          super(schema_element_name_form: "snake_case", &schema_definition)
        end
      end

      def build_preparer(**config_overrides, &schema_definition)
        build_indexer(schema_definition: schema_definition, **config_overrides)
          .record_preparer_factory
          .for_latest_json_schema_version
      end
    end
  end
end
