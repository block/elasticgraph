# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/record_preparer_factory"
require "elastic_graph/spec_support/schema_definition_helpers"
require "support/multiple_version_support"

module ElasticGraph
  module JSONIngestion
    RSpec.describe RecordPreparerFactory, :json_ingestion_schema_definition do
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
        }).then { |indexer| RecordPreparerFactory.new(indexer.schema_artifacts) }
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

    RSpec.describe RecordPreparerFactory, "record preparation for old JSON schema versions", :json_ingestion_schema_definition do
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

          record = preparer.prepare_for_index("MyType", {"id" => "1", "name" => "Winston"}, {})

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

          record = preparer.prepare_for_index("MyType", {"id" => "1", "cost" => {"amount" => 10, "__typename" => "Money"}}, {})

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

          RecordPreparerFactory.new(v2_results).for_json_schema_version(1)
        end

        def define_schema(&schema_definition)
          super(schema_element_name_form: "snake_case", &schema_definition)
        end
      end
    end
  end
end
