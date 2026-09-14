# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/event"
require "elastic_graph/json_ingestion/envelope_validator"

module ElasticGraph
  module JSONIngestion
    RSpec.describe EnvelopeValidator, :capture_logs, :factories, :builds_indexer do
      let(:schema_artifacts) { stock_schema_artifacts }
      let(:indexer) { build_indexer(schema_artifacts: schema_artifacts) }
      let(:envelope_validator) { indexer.ingestion_adapters_by_format.fetch("json").envelope_validator }

      describe "#events_from" do
        it "builds an event from each decoded JSON event with a valid envelope, keeping the format tag" do
          tagged = build_upsert_event_hash(:component, id: "1").merge(INGESTION_FORMAT_KEY => "json")
          untagged = build_upsert_event_hash(:component, id: "2")

          events, failures = envelope_validator.events_from([tagged, untagged])

          expect(failures).to be_empty
          expect(events).to eq [
            ElasticGraph::Indexer::Event.from_validated_hash(tagged),
            ElasticGraph::Indexer::Event.from_validated_hash(untagged)
          ]
          expect(events.map(&:ingestion_format)).to eq ["json", "json"]
        end

        it "returns a `MalformedEventError` for each decoded event with an invalid envelope, alongside the valid events" do
          valid = build_upsert_event_hash(:component, id: "1")
          missing_op = build_upsert_event_hash(:component, id: "2", __version: 3).except("op").merge("message_id" => "m2")
          missing_version = build_upsert_event_hash(:component, id: "3").except("version")

          events, failures = envelope_validator.events_from([missing_op, valid, missing_version])

          expect(events).to eq [ElasticGraph::Indexer::Event.from_validated_hash(valid)]
          expect(failures.map(&:class)).to eq [ElasticGraph::Indexer::MalformedEventError, ElasticGraph::Indexer::MalformedEventError]
          expect(failures.map(&:payload)).to eq [missing_op, missing_version]
          expect(failures.map(&:message_id)).to eq ["m2", nil]
          expect(failures.first.message).to include("Component:2@v3 (message_id: m2): Malformed event payload.", "missing_keys", "op")
          expect(failures.last.message).to start_with("Component:3@v: Malformed event payload.")
        end

        it "notifies an error when latency metrics contain keys that violate regex \"^\\w+_at$\"" do
          event = build_upsert_event_hash(:component, id: "1", __version: 1).merge({
            "latency_timestamps" => {
              "created_in_esperanto_at" => "2012-04-23T18:25:43.511Z",
              "bad metric with spaces _at" => "2012-04-20T18:25:43.511Z",
              "bad_metric" => "2012-04-20T18:25:43.511Z"
            }
          })

          expect_malformed(event, validation_target: "event payload", message_including: ["/latency_timestamps/bad_metric", "bad metric with spaces _at"])
        end

        it "notifies an error when latency metrics contain values that are not ISO8601 date-time" do
          event = build_upsert_event_hash(:component, id: "1", __version: 1).merge({
            "latency_timestamps" => {
              "created_in_esperanto_at" => "2012-04-23T18:25:43.511Z",
              "bad_metric_at" => "malformed datetime"
            }
          })

          expect_malformed(event, validation_target: "event payload", message_including: ["/latency_timestamps/bad_metric"])
        end

        it "notifies an error on version number less than 1" do
          event = build_upsert_event_hash(:widget, __version: -1)

          expect_malformed(event, validation_target: "event payload", message_including: ["/properties/version"])
        end

        it "notifies an error on version number greater than 2^63 - 1" do
          event = build_upsert_event_hash(:widget, __version: 2**64)

          expect_malformed(event, validation_target: "event payload", message_including: ["/properties/version"])
        end

        it "notifies an error on invalid operation" do
          event = build_upsert_event_hash(:widget).merge("op" => "invalid_op")

          expect_malformed(event, validation_target: "event payload", message_including: ["/properties/op"])
        end

        it "notifies an error on missing record for upsert" do
          event = build_upsert_event_hash(:component).except("record")

          expect_malformed(event, validation_target: "event payload", message_including: ["/then"])
        end

        it "notifies an error on missing id" do
          event = build_upsert_event_hash(:component).except("id")

          expect_malformed(event, validation_target: "event payload", message_including: ["missing_keys", "id"])
        end

        it "notifies an error on missing type" do
          event = build_upsert_event_hash(:component).except("type")

          expect_malformed(event, validation_target: "event payload", message_including: ["missing_keys", "type"])
        end

        it "notifies an error on unknown graphql type" do
          event = build_upsert_event_hash(:component).merge("type" => "MyOwnInvalidGraphQlType")

          expect_malformed(event, validation_target: "event payload", message_including: ["/properties/type"])
        end

        it "notifies an error on a graphql type that is not ingestible" do
          event = build_upsert_event_hash(:component).merge("type" => "WidgetOptions")

          expect(indexer.datastore_core.index_definitions_by_graphql_type.fetch("WidgetOptions", [])).to be_empty
          expect_malformed(event, validation_target: "event payload", message_including: ["/properties/type"])
        end

        it "notifies an error on wrong field types" do
          event = {
            "op" => "upsert",
            "id" => 1,
            JSON_SCHEMA_VERSION_KEY => 1,
            "type" => [],
            "version" => "1",
            "record" => ""
          }

          expect_malformed(event, validation_target: "event payload", message_including: ["/properties/type", "/properties/id", "/properties/version", "/properties/record"])
        end

        it "notifies an error on missing `#{JSON_SCHEMA_VERSION_KEY}`" do
          event = build_upsert_event_hash(:component).except(JSON_SCHEMA_VERSION_KEY)

          expect_malformed(event, validation_target: JSON_SCHEMA_VERSION_KEY, message_including: ["Event lacks a `#{JSON_SCHEMA_VERSION_KEY}`"])
        end

        it "notifies an error if an invalid (e.g. negative) json_schema_version is specified" do
          event = build_upsert_event_hash(:widget, id: "1", __version: 1, __json_schema_version: -1)

          expect_malformed(event, validation_target: JSON_SCHEMA_VERSION_KEY, message_including: ["must be a positive integer", "(-1)"])
        end

        it "notifies an error if it's unable to select a json_schema_version" do
          allow(schema_artifacts.extension_artifacts.fetch("json")).to receive(:available_json_schema_versions).and_return(Set[])

          event = build_upsert_event_hash(:component, id: "1", __version: 1)

          expect_malformed(event, validation_target: JSON_SCHEMA_VERSION_KEY, message_including: ["Failed to select json schema version"])
        end

        def expect_malformed(decoded_event, validation_target:, message_including:)
          events, failures = envelope_validator.events_from([decoded_event])

          expect(events).to be_empty
          expect(failures.size).to eq 1
          expect(failures.first.message).to include("Malformed #{validation_target}.", *message_including)
        end
      end
    end
  end
end
