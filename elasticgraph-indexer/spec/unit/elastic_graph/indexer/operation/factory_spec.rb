# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer"
require "elastic_graph/indexer/operation/factory"
require "elastic_graph/json_ingestion/record_preparer_factory"
require "elastic_graph/spec_support/builds_indexer_operation"
require "json"

module ElasticGraph
  class Indexer
    module Operation
      RSpec.describe Factory, :capture_logs do
        describe "#build", :factories do
          include SpecSupport::BuildsIndexerOperation

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
              new_primary_indexing_operation(formatted_event, index_def: index_def_named("widgets")),
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
                new_primary_indexing_operation(usd_event, index_def: index_def_named("widgets"))
              )

              expect(logged_jsons_of_type("SkippingUpdate").size).to eq 1
            end

            it "still generates a derived indexing update for ids that are not configured for this derived, even if those ids are configured for another derived indexing type" do
              cad_event = build_upsert_event(:widget, cost: build(:money, currency: "CAD"))

              expect(build_expecting_success(cad_event)).to contain_exactly(
                new_primary_indexing_operation(cad_event, index_def: index_def_named("widgets")),
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

          it "notifies an error on missing type" do
            event = build_upsert_event(:component).except("type")

            # We can't build any operations when the `type` isn't in the event. We don't know what index to target!
            expect_failed_event_error(event, "missing_keys", "type", expect_no_ops: true)
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

          it "also generates an update operation for related types that have fields `sourced_from` this event type" do
            event = build_upsert_event(:widget, id: "1", __version: 1, component_ids: ["c1", "c2", "c3"])

            operations = build_expecting_success(event).select { |op| op.is_a?(Operation::Update) && op.update_target.type == "Component" }

            expect(operations.size).to eq(3)
            expect(operations.map(&:event)).to all eq event
            expect(operations.map(&:destination_index_def)).to all eq index_def_named("components")
            expect(operations.map(&:doc_id)).to contain_exactly("c1", "c2", "c3")
          end

          context "when multiple ingestion adapters are available" do
            it "routes each event to the first adapter that recognizes it" do
              event = build_upsert_event(:component, id: "1", __version: 1)

              non_matching_adapter = instance_double(IngestionAdapter::Interface, handles_event?: false)
              matching_adapter = instance_double(
                IngestionAdapter::Interface,
                handles_event?: true,
                validate_event: IngestionAdapter::ValidationResult.valid(RecordPreparer::Identity)
              )

              factory = indexer.operation_factory.with(ingestion_adapters: [non_matching_adapter, matching_adapter])
              result = factory.build(event)

              expect(result.failed_event_error).to be nil
              expect(result.operations).not_to be_empty
              expect(matching_adapter).to have_received(:validate_event).with(a_hash_including("type" => "Component"))
            end

            it "fails the event when no adapter recognizes it" do
              event = build_upsert_event(:component, id: "1", __version: 1)

              adapters = [
                instance_double(IngestionAdapter::Interface, handles_event?: false),
                instance_double(IngestionAdapter::Interface, handles_event?: false)
              ]

              factory = indexer.operation_factory.with(ingestion_adapters: adapters)

              expect_failed_event_error(event, "No available ingestion adapter recognized this event.", factory: factory)
            end
          end

          context "when a single ingestion adapter is available" do
            it "routes all events to it, even ones it does not recognize, so that its more specific failure messages are used" do
              event = build_upsert_event(:component, id: "1", __version: 1)

              adapter = instance_double(
                IngestionAdapter::Interface,
                handles_event?: false,
                validate_event: IngestionAdapter::ValidationResult.invalid(
                  payload_description: "event payload",
                  message: "not recognizable by this adapter"
                )
              )

              factory = indexer.operation_factory.with(ingestion_adapters: [adapter])

              expect_failed_event_error(event, "not recognizable by this adapter", factory: factory)
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

        def build_expecting_success(event, **options)
          result = indexer.operation_factory.build(event, **options)

          expect(result.failed_event_error).to be nil
          result.operations
        end

        def widget_currency_derived_update_operation_for(event)
          operations = Update.operations_for(
            event: event,
            destination_index_def: index_def_named("widget_currencies"),
            record_preparer: JSONIngestion::RecordPreparerFactory.new(indexer.schema_artifacts).for_latest_json_schema_version,
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
