# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/ingestion_schemas/json_schema"

module ElasticGraph
  class Indexer
    module IngestionSchemas
      RSpec.describe JSONSchema do
        let(:indexer) { build_indexer }
        let(:schema_artifacts) { indexer.schema_artifacts }
        let(:record_preparer_factory) { indexer.record_preparer_factory }

        it "delegates available versions to schema artifacts" do
          ingestion_schema = JSONSchema.new(
            schema_artifacts: schema_artifacts,
            record_preparer_factory: record_preparer_factory,
            configure_record_validator: nil
          )

          expect(ingestion_schema.available_versions).to eq(schema_artifacts.available_json_schema_versions)
        end

        it "delegates record preparer selection to RecordPreparer::Factory" do
          ingestion_schema = JSONSchema.new(
            schema_artifacts: schema_artifacts,
            record_preparer_factory: record_preparer_factory,
            configure_record_validator: nil
          )

          expect(ingestion_schema.record_preparer_for(1)).to be(record_preparer_factory.for_json_schema_version(1))
        end

        it "builds and memoizes validator factories by schema version" do
          configure_calls = 0

          ingestion_schema = JSONSchema.new(
            schema_artifacts: schema_artifacts,
            record_preparer_factory: record_preparer_factory,
            configure_record_validator: lambda { |factory|
              configure_calls += 1
              factory
            }
          )

          first_validator = ingestion_schema.validator_for(EVENT_ENVELOPE_JSON_SCHEMA_NAME, 1)
          second_validator = ingestion_schema.validator_for(EVENT_ENVELOPE_JSON_SCHEMA_NAME, 1)

          expect(configure_calls).to eq(1)
          expect(first_validator).to be(second_validator)
        end

        it "loads distinct validator factories for distinct schema versions" do
          alternate_schema = ::Marshal.load(::Marshal.dump(schema_artifacts.json_schemas_for(1))).tap do |schema|
            schema[JSON_SCHEMA_VERSION_KEY] = 2
            schema["$defs"]["ElasticGraphEventEnvelope"]["properties"][JSON_SCHEMA_VERSION_KEY]["const"] = 2
          end

          fake_schema_artifacts = instance_double(
            "ElasticGraph::SchemaArtifacts::FromDisk",
            available_json_schema_versions: Set[1, 2],
            json_schemas_for: nil
          )

          allow(fake_schema_artifacts).to receive(:json_schemas_for) do |version|
            (version == 1) ? schema_artifacts.json_schemas_for(1) : alternate_schema
          end

          configure_calls = 0
          ingestion_schema = JSONSchema.new(
            schema_artifacts: fake_schema_artifacts,
            record_preparer_factory: record_preparer_factory,
            configure_record_validator: lambda { |factory|
              configure_calls += 1
              factory
            }
          )

          ingestion_schema.validator_for(EVENT_ENVELOPE_JSON_SCHEMA_NAME, 1)
          ingestion_schema.validator_for(EVENT_ENVELOPE_JSON_SCHEMA_NAME, 2)

          expect(configure_calls).to eq(2)
        end
      end
    end
  end
end
