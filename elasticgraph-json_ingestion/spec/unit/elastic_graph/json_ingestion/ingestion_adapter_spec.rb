# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/json_ingestion/ingestion_adapter"

module ElasticGraph
  module JSONIngestion
    RSpec.describe IngestionAdapter, :capture_logs, :factories do
      let(:schema_artifacts) { stock_schema_artifacts }
      let(:adapter) { build_adapter }

      describe "#handles_event?" do
        it "recognizes events that have a `#{JSON_SCHEMA_VERSION_KEY}` in their envelope" do
          event = build_upsert_event(:component)

          expect(adapter.handles_event?(event)).to be true
          expect(adapter.handles_event?(event.except(JSON_SCHEMA_VERSION_KEY))).to be false
        end
      end

      describe "#validate_event" do
        it "returns a valid result with a record preparer for the event's JSON schema version" do
          event = build_upsert_event(:component)

          result = adapter.validate_event(event)

          expect(result.failure).to be nil
          expect(result.record_preparer.prepare_for_index("Component", {"id" => "1", "unknown_field" => 3}, {}))
            .to eq({"id" => "1"})
        end

        it "notifies an error when latency metrics contain keys that violate regex \"^\\w+_at$\"" do
          event = build_upsert_event(:component, id: "1", __version: 1).merge({
            "latency_timestamps" => {
              "created_in_esperanto_at" => "2012-04-23T18:25:43.511Z",
              "bad metric with spaces _at" => "2012-04-20T18:25:43.511Z",
              "bad_metric" => "2012-04-20T18:25:43.511Z"
            }
          })

          expect_invalid(event, payload_description: "event payload", message_including: ["/latency_timestamps/bad_metric", "bad metric with spaces _at"])
        end

        it "notifies an error when latency metrics contain values that are not ISO8601 date-time" do
          event = build_upsert_event(:component, id: "1", __version: 1).merge({
            "latency_timestamps" => {
              "created_in_esperanto_at" => "2012-04-23T18:25:43.511Z",
              "bad_metric_at" => "malformed datetime"
            }
          })

          expect_invalid(event, payload_description: "event payload", message_including: ["/latency_timestamps/bad_metric"])
        end

        it "notifies an error on version number less than 1" do
          event = build_upsert_event(:widget, __version: -1)

          expect_invalid(event, payload_description: "event payload", message_including: ["/properties/version"])
        end

        it "notifies an error on version number greater than 2^63 - 1" do
          event = build_upsert_event(:widget, __version: 2**64)

          expect_invalid(event, payload_description: "event payload", message_including: ["/properties/version"])
        end

        it "notifies an error on invalid operation" do
          event = build_upsert_event(:widget).merge("op" => "invalid_op")

          expect_invalid(event, payload_description: "event payload", message_including: ["/properties/op"])
        end

        it "notifies an error on missing operation" do
          event = build_upsert_event(:widget).except("op")

          expect_invalid(event, payload_description: "event payload", message_including: ["missing_keys", "op"])
        end

        it "notifies an error on missing record for upsert" do
          event = build_upsert_event(:component).except("record")

          expect_invalid(event, payload_description: "event payload", message_including: ["/then"])
        end

        it "notifies an error on missing id" do
          event = build_upsert_event(:component).except("id")

          expect_invalid(event, payload_description: "event payload", message_including: ["missing_keys", "id"])
        end

        it "notifies an error on missing version" do
          event = build_upsert_event(:component).except("version")

          expect_invalid(event, payload_description: "event payload", message_including: ["missing_keys", "version"])
        end

        it "notifies an error on missing `#{JSON_SCHEMA_VERSION_KEY}`" do
          event = build_upsert_event(:component).except(JSON_SCHEMA_VERSION_KEY)

          expect_invalid(event, payload_description: JSON_SCHEMA_VERSION_KEY, message_including: ["Event lacks a `#{JSON_SCHEMA_VERSION_KEY}`"])
        end

        it "notifies an error when given a record that does not satisfy the type's JSON schema, while avoiding revealing PII" do
          event = build_upsert_event(:component, id: "1", __version: 1)
          event["record"]["name"] = 123

          message = expect_invalid(event, payload_description: "Component record", message_including: ["name"])
          expect(message).to exclude("123")
        end

        it "allows the record validator to be configured with a block" do
          event_with_extra_field = build_upsert_event(:widget, extra_field: 17)
          event_with_extra_field["record"]["extra_field"] = 17

          expect(adapter.validate_event(event_with_extra_field).failure).to be nil

          configured_adapter = build_adapter { |v| v.with_unknown_properties_disallowed }
          failure = configured_adapter.validate_event(event_with_extra_field).failure

          expect(failure.message).to include("extra_field")
        end

        context "when the adapter has json schemas v2 and v4 (v4 adds yellow color)" do
          before do
            # With the "real" version one as a baseline, create a separate version with a small schema change.
            # Tests will then specify the desired json_schema_version in the event payload to test the schema-choosing
            # behavior of the adapter.
            schemas = {
              2 => schema_artifacts.json_schemas_for(1),
              4 => ::Marshal.load(::Marshal.dump(schema_artifacts.json_schemas_for(1))).tap do |schema|
                schema["$defs"]["Color"]["enum"] << "YELLOW"
              end
            }

            allow(schema_artifacts).to receive(:available_json_schema_versions).and_return(schemas.keys.to_set)
            allow(schema_artifacts).to receive(:latest_json_schema_version).and_return(schemas.keys.max)
            allow(schema_artifacts).to receive(:json_schemas_for) do |version|
              ::Marshal.load(::Marshal.dump(schemas.fetch(version))).tap do |schema|
                schema[JSON_SCHEMA_VERSION_KEY] = version
                schema["$defs"]["ElasticGraphEventEnvelope"]["properties"][JSON_SCHEMA_VERSION_KEY]["const"] = version
              end
            end
          end

          it "validates against an older version of a json schema if specified" do
            # YELLOW doesn't exist in schema version 2. So expect an error when json_schema_version is set to 2.
            event = build_upsert_event(:widget, id: "1", __version: 1, __json_schema_version: 2)
            event["record"]["options"]["color"] = "YELLOW"

            expect_invalid(event, payload_description: "Widget record", message_including: ["/options/color"])
          end

          it "validates against the latest version of a json schema if specified" do
            event = build_upsert_event(:widget, id: "1", __version: 1, __json_schema_version: 4)
            event["record"]["options"]["color"] = "YELLOW"

            expect(adapter.validate_event(event).failure).to be nil
          end

          it "validates against the closest version if the requested version is newer than what's available" do
            # 5 is closest to "4", validation should match behavior from version "4" - YELLOW should pass validation.
            event = build_upsert_event(:widget, id: "1", __version: 1, __json_schema_version: 5)
            event["record"]["options"]["color"] = "YELLOW"

            expect(adapter.validate_event(event).failure).to be nil

            expect(logged_jsons_of_type("ElasticGraphMissingJSONSchemaVersion").last).to include(
              "event_id" => "Widget:1@v1",
              "event_type" => "Widget",
              "requested_json_schema_version" => 5,
              "selected_json_schema_version" => 4
            )
          end

          it "validates against the closest version if the requested version older than what's available" do
            # 1 is closest to "2", validation should match behavior from version "2" - YELLOW should fail validation.
            event = build_upsert_event(:widget, id: "1", __version: 1, __json_schema_version: 1).merge("message_id" => "m123")
            event["record"]["options"]["color"] = "YELLOW"

            # Should fail, but should still log the version mismatch as well.
            expect_invalid(event, payload_description: "Widget record", message_including: ["/options/color"])

            expect(logged_jsons_of_type("ElasticGraphMissingJSONSchemaVersion").last).to include(
              "event_id" => "Widget:1@v1",
              "message_id" => "m123",
              "event_type" => "Widget",
              "requested_json_schema_version" => 1,
              "selected_json_schema_version" => 2
            )
          end

          it "validates against a version newer than what's requested, if the requested version is equidistant from two available versions" do
            event = build_upsert_event(:widget, id: "1", __version: 1, __json_schema_version: 3)
            event["record"]["options"]["color"] = "YELLOW"

            expect(adapter.validate_event(event).failure).to be nil

            expect(logged_jsons_of_type("ElasticGraphMissingJSONSchemaVersion").last).to include(
              "event_id" => "Widget:1@v1",
              "event_type" => "Widget",
              "requested_json_schema_version" => 3,
              "selected_json_schema_version" => 4
            )
          end

          it "notifies an error if an invalid (e.g. negative) json_schema_version is specified" do
            event = build_upsert_event(:widget, id: "1", __version: 1, __json_schema_version: -1)

            expect_invalid(event, payload_description: JSON_SCHEMA_VERSION_KEY, message_including: ["must be a positive integer", "(-1)"])
          end
        end

        it "notifies an error if it's unable to select a json_schema_version" do
          allow(schema_artifacts).to receive(:available_json_schema_versions).and_return(Set[])

          event = build_upsert_event(:component, id: "1", __version: 1)

          expect_invalid(event, payload_description: JSON_SCHEMA_VERSION_KEY, message_including: ["Failed to select json schema version"])
        end

        def expect_invalid(event, payload_description:, message_including:)
          result = adapter.validate_event(event)

          expect(result.record_preparer).to be nil

          failure = result.failure
          expect(failure.payload_description).to eq(payload_description)
          expect(failure.message).to include(*message_including)

          failure.message
        end
      end

      def build_adapter(&configure_record_validator)
        IngestionAdapter.new(
          schema_artifacts: schema_artifacts,
          logger: logger,
          configure_record_validator: configure_record_validator
        )
      end
    end
  end
end
