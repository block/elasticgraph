# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer"
require "elastic_graph/constants"
require "elastic_graph/indexer/operation/factory"
require "json"

module ElasticGraph
  class Indexer
    module Operation
      RSpec.describe Factory, :capture_logs do
        describe "#build", :factories do
          shared_examples_for "building operations" do
            let(:indexer) { build_indexer }
            let(:component_index_definition) { index_def_named("components") }

            it "generates a primary indexing operation" do
              event = build_upsert_event(:component, id: "1", __version: 1)

              expect(build_expecting_success(event)).to eq([new_primary_indexing_operation(event)])
            end

            it "also generates derived index update operations for an upsert event for the source type of a derived indexing type" do
              event = build_upsert_event(:widget, id: "1", __version: 1)
              formatted_event = {
                "op" => "upsert",
                "id" => "1",
                "type" => "Widget",
                "version" => 1,
                "record" => event["record"],
                JSON_SCHEMA_VERSION_KEY => 1
              }

              expect(build_expecting_success(event)).to contain_exactly(
                new_primary_indexing_operation(formatted_event, index_def_named("widgets")),
                widget_currency_derived_update_operation_for(formatted_event)
              )
            end

            context "when the indexer is configured to skip updates for certain derived indexing types and ids" do
              let(:indexer) do
                build_indexer(skip_derived_indexing_type_updates: {
                  "WidgetCurrency" => ["USD"],
                  "SomeOtherType" => ["CAD"]
                })
              end

              it "skips generating a derived indexing update when the id is configured to be skipped" do
                usd_event = build_upsert_event(:widget, cost: build(:money, currency: "USD"))

                expect(build_expecting_success(usd_event)).to contain_exactly(
                  new_primary_indexing_operation(usd_event, index_def_named("widgets"))
                )

                expect(logged_jsons_of_type("SkippingUpdate").size).to eq 1
              end

              it "still generates a derived indexing update for ids that are not configured for this derived, even if those ids are configured for another derived indexing type" do
                cad_event = build_upsert_event(:widget, cost: build(:money, currency: "CAD"))

                expect(build_expecting_success(cad_event)).to contain_exactly(
                  new_primary_indexing_operation(cad_event, index_def_named("widgets")),
                  widget_currency_derived_update_operation_for(cad_event)
                )

                expect(logged_jsons_of_type("SkippingUpdate").size).to eq 0
              end
            end

            it "generates a primary indexing operation for a single index with latency metrics" do
              event = build_upsert_event(:component, id: "1", __version: 1)
              latency_timestamps = {"latency_timestamps" => {"created_in_esperanto_at" => "2012-04-23T18:25:43.511Z"}}

              expect(build_expecting_success(event.merge(latency_timestamps))).to eq([new_primary_indexing_operation({
                "op" => "upsert",
                "id" => "1",
                "type" => "Component",
                "version" => 1,
                "record" => event["record"],
                JSON_SCHEMA_VERSION_KEY => 1
              }.merge(latency_timestamps))])
            end

            it 'notifies an error when latency metrics contain keys that violate regex "^\\w+_at$"' do
              valid_event = build_upsert_event(:component, id: "1", __version: 1)
              invalid_event = valid_event.merge({
                "latency_timestamps" => {
                  "created_in_esperanto_at" => "2012-04-23T18:25:43.511Z",
                  "bad metric with spaces _at" => "2012-04-20T18:25:43.511Z",
                  "bad_metric" => "2012-04-20T18:25:43.511Z"
                }
              })

              expect_failed_event_error(invalid_event, "/latency_timestamps/bad_metric", "bad metric with spaces _at")
            end

            it "notifies an error when latency metrics contain values that are not ISO8601 date-time" do
              valid_event = build_upsert_event(:component, id: "1", __version: 1)
              invalid_event = valid_event.merge({
                "latency_timestamps" => {
                  "created_in_esperanto_at" => "2012-04-23T18:25:43.511Z",
                  "bad_metric_at" => "malformed datetime"
                }
              })

              expect_failed_event_error(invalid_event, "/latency_timestamps/bad_metric")
            end

            it "notifies an error on version number less than 1" do
              event = build_upsert_event(:widget, __version: -1)

              expect_failed_event_error(event, "/properties/version")
            end

            it "notifies an error on version number greater than 2^63 - 1" do
              event = build_upsert_event(:widget, __version: 2**64)

              expect_failed_event_error(event, "/properties/version")
            end

            it "notifies an error on unknown graphql type" do
              event = {
                "op" => "upsert",
                "id" => "1",
                "type" => "MyOwnInvalidGraphQlType",
                "version" => 1,
                JSON_SCHEMA_VERSION_KEY => 1,
                "record" => {"field1" => "value1", "field2" => "value2", "id" => "1"}
              }

              # We can't build any operations when the `type` is unknown. We don't know what index to target!
              expect_failed_event_error(event, "/properties/type", expect_no_ops: true)
            end

            it "notifies an error on non-indexed graphql type" do
              event = {
                "op" => "upsert",
                "id" => "1",
                "type" => "WidgetOptions",
                "version" => 1,
                JSON_SCHEMA_VERSION_KEY => 1,
                "record" => {"field1" => "value1", "field2" => "value2", "id" => "1"}
              }

              expect(indexer.datastore_core.index_definitions_by_graphql_type.fetch(event.fetch("type"), [])).to be_empty

              # We can't build any operations when the `type` isn't an indexed type. We don't know what index to target!
              expect_failed_event_error(event, "/properties/type", expect_no_ops: true)
            end

            it "notifies an error on invalid operation" do
              event = build_upsert_event(:widget).merge("op" => "invalid_op")

              expect_failed_event_error(event, "/properties/op")
            end

            it "notifies an error on missing operation" do
              event = build_upsert_event(:widget).except("op")

              expect_failed_event_error(event, "missing_keys", "op")
            end

            it "notifies an error on missing record for upsert" do
              event = build_upsert_event(:component).except("record")

              expect_failed_event_error(event, "/then")
            end

            it "notifies an error on missing id" do
              event = build_upsert_event(:component).except("id")

              expect_failed_event_error(event, "missing_keys", "id")
            end

            it "notifies an error on missing type" do
              event = build_upsert_event(:component).except("type")

              # We can't build any operations when the `type` isn't in the event. We don't know what index to target!
              expect_failed_event_error(event, "missing_keys", "type", expect_no_ops: true)
            end

            it "notifies an error on missing version" do
              event = build_upsert_event(:component).except("version")

              expect_failed_event_error(event, "missing_keys", "version")
            end

            it "notifies an error on missing `#{JSON_SCHEMA_VERSION_KEY}`" do
              event = build_upsert_event(:component).except(JSON_SCHEMA_VERSION_KEY)

              expect_failed_event_error(event, JSON_SCHEMA_VERSION_KEY)
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

              # This event is too malformed to build any operations for.
              expect_failed_event_error(event, "/properties/type", "/properties/id", "/properties/version", "/properties/record", expect_no_ops: true)
            end

            it "notifies an error when given a record that does not satisfy the type's JSON schema, while avoiding revealing PII" do
              event = build_upsert_event(:component, id: "1", __version: 1)
              event["record"]["name"] = 123

              message = expect_failed_event_error(event, "Malformed", "Component", "name")
              expect(message).to include("Malformed").and exclude("123")
            end

            it "requires that a custom shard routing field have a non-empty value" do
              good_widget = build_upsert_event(:widget, workspace_id: "good_value")
              bad_widget1 = build_upsert_event(:widget, workspace_id: nil) # routing value can't be nil
              bad_widget2 = build_upsert_event(:widget, workspace_id: "") # routing value can't be an empty string
              bad_widget3 = build_upsert_event(:widget, workspace_id: " ") # routing value can't be entirely whitespace

              expect(build_expecting_success(good_widget).size).to eq(2)

              expect_failed_event_error(bad_widget1, "/workspace_id")
              expect_failed_event_error(bad_widget2, "/workspace_id")
              expect_failed_event_error(bad_widget3, "/workspace_id")
            end

            it "allows the validator to be configured with a block" do
              event_with_extra_field = build_upsert_event(:widget, extra_field: 17)

              expect {
                build_expecting_success(event_with_extra_field)
              }.not_to raise_error

              expect {
                build_expecting_success(event_with_extra_field) { |v| v.with_unknown_properties_disallowed }
              }.to raise_error FailedEventError, a_string_including("extra_field")
            end

            context "when the indexer has json schemas v2 and v4 (v4 adds yellow color)" do
              before do
                # With the "real" version one as a baseline, create a separate version with a small schema change.
                # Tests will then specify the desired json_schema_version in the event payload to test the schema-choosing
                # behavior of the `factory` class.
                schemas = {
                  2 => indexer.schema_artifacts.json_schemas_for(1),
                  4 => ::Marshal.load(::Marshal.dump(indexer.schema_artifacts.json_schemas_for(1))).tap do |it|
                    it["$defs"]["Color"]["enum"] << "YELLOW"
                  end
                }

                allow(indexer.schema_artifacts).to receive(:available_json_schema_versions).and_return(schemas.keys.to_set)
                allow(indexer.schema_artifacts).to receive(:latest_json_schema_version).and_return(schemas.keys.max)
                allow(indexer.schema_artifacts).to receive(:json_schemas_for) do |version|
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

                expect_failed_event_error(event, "/options/color")
              end

              it "validates against the latest version of a json schema if specified" do
                event = build_upsert_event(:widget, id: "1", __version: 1, __json_schema_version: 4)
                event["record"]["options"]["color"] = "YELLOW"

                expect(build_expecting_success(event)).to include(new_primary_indexing_operation({
                  "op" => "upsert",
                  "id" => "1",
                  "type" => "Widget",
                  "version" => 1,
                  "record" => event["record"],
                  JSON_SCHEMA_VERSION_KEY => 4
                }, index_def_named("widgets")))
              end

              it "validates against the closest version if the requested version is newer than what's available" do
                # 5 is closest to "4", validation should match behavior from version "4" - YELLOW should pass validation.
                event = build_upsert_event(:widget, id: "1", __version: 1, __json_schema_version: 5)
                event["record"]["options"]["color"] = "YELLOW"

                expect(build_expecting_success(event)).to include(new_primary_indexing_operation({
                  "op" => "upsert",
                  "id" => "1",
                  "type" => "Widget",
                  "version" => 1,
                  "record" => event["record"],
                  JSON_SCHEMA_VERSION_KEY => 5 # Originally-specified version.
                }, index_def_named("widgets")))

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
                expect_failed_event_error(
                  event,
                  "Malformed Widget record",
                  "1",
                  "/options/color"
                )

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

                expect(build_expecting_success(event)).to include(new_primary_indexing_operation({
                  "op" => "upsert",
                  "id" => "1",
                  "type" => "Widget",
                  "version" => 1,
                  "record" => event["record"],
                  JSON_SCHEMA_VERSION_KEY => 3 # Originally-specified version.
                }, index_def_named("widgets")))

                expect(logged_jsons_of_type("ElasticGraphMissingJSONSchemaVersion").last).to include(
                  "event_id" => "Widget:1@v1",
                  "event_type" => "Widget",
                  "requested_json_schema_version" => 3,
                  "selected_json_schema_version" => 4
                )
              end

              it "notifies an error if an invalid (e.g. negative) json_schema_version is specified" do
                event = build_upsert_event(:widget, id: "1", __version: 1, __json_schema_version: -1)

                expect_failed_event_error(event, "must be a positive integer", "(-1)")
              end

              it "notifies an error if it's unable to select a json_schema_version" do
                event = build_upsert_event(:component, id: "1", __version: 1)
                event["record"]["name"] = 123

                fake_empty_schema_artifacts = instance_double(
                  "ElasticGraph::SchemaArtifacts::FromDisk",
                  available_json_schema_versions: Set[],
                  runtime_metadata: indexer.schema_artifacts.runtime_metadata,
                  indices: indexer.schema_artifacts.indices,
                  index_templates: indexer.schema_artifacts.index_templates,
                  index_mappings_by_index_def_name: indexer.schema_artifacts.index_mappings_by_index_def_name
                )

                operation_factory = build_indexer(schema_artifacts: fake_empty_schema_artifacts).operation_factory

                expect_failed_event_error(event, "Failed to select json schema version", factory: operation_factory)
              end
            end
          end

          context "when `use_updates_for_indexing?` is set to false", use_updates_for_indexing: false do
            include_examples "building operations" do
              def new_primary_indexing_operation(event, index_def = component_index_definition, idxr = indexer)
                Upsert.new(
                  event,
                  index_def,
                  idxr.record_preparer_factory.for_latest_json_schema_version
                )
              end
            end
          end

          context "when `use_updates_for_indexing?` is set to true", use_updates_for_indexing: true do
            include_examples "building operations" do
              it "also generates an update operation for related types that have fields `sourced_from` this event type" do
                event = build_upsert_event(:widget, id: "1", __version: 1, component_ids: ["c1", "c2", "c3"])

                operations = build_expecting_success(event).select { |op| op.is_a?(Operation::Update) && op.update_target.type == "Component" }

                expect(operations.size).to eq(3)
                expect(operations.map(&:event)).to all eq event
                expect(operations.map(&:destination_index_def)).to all eq index_def_named("components")
                expect(operations.map(&:doc_id)).to contain_exactly("c1", "c2", "c3")
              end

              def new_primary_indexing_operation(event, index_def = component_index_definition, idxr = indexer)
                update_targets = idxr
                  .schema_artifacts
                  .runtime_metadata
                  .object_types_by_name
                  .fetch(event.fetch("type"))
                  .update_targets
                  .select { |ut| ut.type == event.fetch("type") }

                expect(update_targets.size).to eq(1)

                Update.new(
                  event: event,
                  prepared_record: indexer.record_preparer_factory.for_latest_json_schema_version.prepare_for_index(
                    event.fetch("type"),
                    event.fetch("record")
                  ),
                  destination_index_def: index_def,
                  update_target: update_targets.first,
                  doc_id: event.fetch("id"),
                  destination_index_mapping: idxr.schema_artifacts.index_mappings_by_index_def_name.fetch(index_def.name)
                )
              end
            end
          end

          def expect_failed_event_error(event, *error_message_snippets, factory: indexer.operation_factory, expect_no_ops: false)
            result = factory.build(event)

            error_operations = factory.send(:build_all_operations_for, event, RecordPreparer::Identity)

            # We expect/want `build_all_operations_for` to return operations in nearly all cases.
            # There are a few cases where it can't return any operations, so we make the test pass
            # `expect_no_ops` to opt-in to allowing that here.
            if expect_no_ops
              expect(error_operations).to be_empty
            else
              expect(error_operations).not_to be_empty
            end

            # When the event is invalid it should return an empty list of operations.
            expect(result.operations).to eq([])

            failure = result.failed_event_error

            expect(failure).to be_an(FailedEventError)
            expect(failure.event).to eq(event)
            expect(failure.operations).to match_array(error_operations)
            expect(failure.message).to include(event_id_from(event), *error_message_snippets)
            expect(failure.main_message).to include(*error_message_snippets).and exclude(event_id_from(event))
            expect(failure).to have_attributes(
              id: event["id"],
              type: event["type"],
              op: event["op"],
              version: event["version"],
              record: event["record"]
            )

            failure.message # to allow the caller to assert on the message further
          end

          def event_id_from(event)
            Indexer::EventID.from_event(event).to_s
          end
        end

        def build_expecting_success(event, **options, &configure_record_validator)
          result = indexer
            .operation_factory
            .with(configure_record_validator: configure_record_validator)
            .build(event, **options)

          raise result.failed_event_error if result.failed_event_error
          result.operations
        end

        def widget_currency_derived_update_operation_for(event)
          operations = Update.operations_for(
            event: event,
            destination_index_def: index_def_named("widget_currencies"),
            record_preparer: indexer.record_preparer_factory.for_latest_json_schema_version,
            update_target: indexer.schema_artifacts.runtime_metadata.object_types_by_name.fetch("Widget").update_targets.first,
            destination_index_mapping: indexer.schema_artifacts.index_mappings_by_index_def_name.fetch("widget_currencies")
          )

          expect(operations.size).to be < 2
          operations.first
        end

        def index_def_named(index_def_name)
          indexer.datastore_core.index_definitions_by_name.fetch(index_def_name)
        end
      end
    end
  end
end
