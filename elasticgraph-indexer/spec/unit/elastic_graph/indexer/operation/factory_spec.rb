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
              SCHEMA_VERSION_KEY => 1
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

          # We deliberately construct the indexer here without going through `build_indexer`. The
          # `skip_record_validation_percents_by_type` knob is intentionally not exposed via spec helpers so that
          # tests cannot silently weaken validation; enabling it must be a visible, deliberate choice
          # in each spec that exercises it.
          context "when the indexer is configured to skip record validation for some types" do
            let(:indexer) do
              datastore_core = build_datastore_core
              Indexer.new(
                datastore_core: datastore_core,
                config: Indexer::Config.new(
                  latency_slo_thresholds_by_timestamp_in_ms: {},
                  skip_derived_indexing_type_updates: {},
                  skip_record_validation_percents_by_type: {"Component" => 100}
                )
              )
            end

            it "skips per-type record validation for the listed type but still builds operations" do
              event = build_upsert_event(:component, id: "1", __version: 1)
              event["record"]["name"] = 123 # would normally fail JSON schema validation

              expect(build_expecting_success(event)).to eq([new_primary_indexing_operation({
                "op" => "upsert",
                "id" => "1",
                "type" => "Component",
                "version" => 1,
                "record" => event["record"],
                SCHEMA_VERSION_KEY => 1
              })])
            end

            it "records the skipped type on the successful build result" do
              event = build_upsert_event(:component, id: "1", __version: 1)

              result = indexer.operation_factory.build(event)

              expect(result.type_with_skipped_validation).to eq("Component")
            end

            it "still validates record-level fields for types that are not in the skip list" do
              widget_event = build_upsert_event(:widget, id: "1", __version: 1)
              widget_event["record"]["name"] = 123

              expect_failed_event_error(widget_event, "Malformed Widget record", "name")
            end

            it "does not flag validated types on the successful build result" do
              event = build_upsert_event(:widget, id: "1", __version: 1)

              result = indexer.operation_factory.build(event)

              expect(result.type_with_skipped_validation).to be_nil
            end

            it "still applies envelope-level validation for skipped types" do
              event = build_upsert_event(:component, id: "1", __version: -1)

              expect_failed_event_error(event, "/properties/version")
            end
          end

          context "when the indexer configures a partial skip percent for a type" do
            let(:indexer) do
              datastore_core = build_datastore_core
              Indexer.new(
                datastore_core: datastore_core,
                config: Indexer::Config.new(
                  latency_slo_thresholds_by_timestamp_in_ms: {},
                  skip_derived_indexing_type_updates: {},
                  skip_record_validation_percents_by_type: {"Component" => 50}
                )
              )
            end

            it "skips validation when the event's point in the crc32 space falls in the skipped portion" do
              # Stub crc32 to the bottom of the space -- well inside the skipped 50% -- forcing the "skip" branch.
              allow(::Zlib).to receive(:crc32).and_return(0)

              event = build_upsert_event(:component, id: "1", __version: 1)
              event["record"]["name"] = 123 # would normally fail JSON schema validation

              expect {
                build_expecting_success(event)
              }.not_to raise_error
            end

            it "still validates when the event's point in the crc32 space falls outside the skipped portion" do
              # Stub crc32 to 75% of the way through the space, past the skipped 50%, forcing validation.
              allow(::Zlib).to receive(:crc32).and_return((2**32 * 0.75).to_i)

              event = build_upsert_event(:component, id: "1", __version: 1)
              event["record"]["name"] = 123

              expect_failed_event_error(event, "Malformed Component record", "name")
            end

            it "produces the same skip decision for the same event on retry" do
              # No stubbing -- this exercises the real crc32 and locks in determinism without
              # coupling to a specific hash output. Two builds of the same event must agree on
              # whether to skip validation.
              event = build_upsert_event(:component, id: "1", __version: 1)
              event["record"]["name"] = 123 # would fail validation if not skipped

              first = indexer.operation_factory.build(event)
              second = indexer.operation_factory.build(event)

              expect(first.failed_event_error.nil?).to eq(second.failed_event_error.nil?)
              expect(first.operations.size).to eq(second.operations.size)
              expect(first.type_with_skipped_validation).to eq(second.type_with_skipped_validation)
            end
          end

          context "when record validation is skipped for a type that has derived-index update targets" do
            # Widget has a `WidgetCurrency` derived index update target. With validation skipped,
            # `build_all_operations_for` still has to traverse `Update.operations_for` and the
            # schema artifacts. This spec locks in that skipping does not regress the derived path.
            let(:indexer) do
              datastore_core = build_datastore_core
              Indexer.new(
                datastore_core: datastore_core,
                config: Indexer::Config.new(
                  latency_slo_thresholds_by_timestamp_in_ms: {},
                  skip_derived_indexing_type_updates: {},
                  skip_record_validation_percents_by_type: {"Widget" => 100}
                )
              )
            end

            it "still emits both the primary and the derived-index update operations" do
              event = build_upsert_event(:widget, id: "1", __version: 1)
              formatted_event = {
                "op" => "upsert",
                "id" => "1",
                "type" => "Widget",
                "version" => 1,
                "record" => event["record"],
                SCHEMA_VERSION_KEY => 1
              }

              expect(build_expecting_success(event)).to contain_exactly(
                new_primary_indexing_operation(formatted_event, index_def: index_def_named("widgets")),
                widget_currency_derived_update_operation_for(formatted_event)
              )
            end
          end

          context "when building the operations for a record whose validation was skipped raises" do
            # These specs cover the re-validation gate: an exception escaping operation building is
            # answered by running the validation we skipped. If the validator faults the record, the
            # caller gets the same failure it would have gotten had we validated up front. If the
            # validator is happy, the error was never about the data and must not be swallowed.
            let(:indexer) do
              datastore_core = build_datastore_core
              Indexer.new(
                datastore_core: datastore_core,
                config: Indexer::Config.new(
                  latency_slo_thresholds_by_timestamp_in_ms: {},
                  skip_derived_indexing_type_updates: {},
                  skip_record_validation_percents_by_type: {"Widget" => 100}
                )
              )
            end

            it "reports a value the indexing preparers can't coerce as a failed event carrying the validator's message" do
              event = build_upsert_event(:widget, id: "1", __version: 1)
              # `IndexingPreparers::Integer` raises `Errors::IndexOperationError` on this; validation
              # would have caught it first as a type mismatch on `amount_cents`.
              event["record"]["cost"] = {"currency" => "USD", "amount_cents" => "not a number"}

              message = expect_failed_event_error(event, "Malformed Widget record", "amount_cents")

              expect(message).to exclude("IndexOperationError")
            end

            it "reports a missing or unknown abstract-type `__typename` as a failed event carrying the validator's message" do
              # Widget's `inventor` field is the `Inventor` union, whose JSON schema requires
              # `__typename` and pins a `const` discriminator on each concrete subtype. Both the
              # missing and the unknown case therefore fail validation, which is why no dedicated
              # error type is needed for them.
              event = build_upsert_event(:widget, id: "1", __version: 1)
              event["record"]["inventor"] = {"__typename" => "NotARealConcreteType", "name" => "anon"}

              expect_failed_event_error(event, "Malformed Widget record", "inventor")
            end

            it "re-raises an error the validator has no opinion about, so bugs are not hidden as data failures" do
              event = build_upsert_event(:widget, id: "1", __version: 1)

              # Asserting on class *and* message matters here: `raise` is overridden on
              # `Operation::Factory` to reject raising from the class, so a bare `raise exception`
              # would substitute the guard's own error and still satisfy a bare `raise_error`.
              expect {
                factory_whose_record_preparation_is_broken.build(event)
              }.to raise_error(::KeyError, a_string_including("nameInIndex"))
            end
          end

          it "does not rescue when validation was not skipped, so the validated path behaves exactly as before" do
            event = build_upsert_event(:widget, id: "1", __version: 1)

            expect {
              factory_whose_record_preparation_is_broken.build(event)
            }.to raise_error(::KeyError, a_string_including("nameInIndex"))
          end

          context "when an event is malformed in a way that also breaks building its operations", :expect_warning_logging do
            # `Widget` requires `cost`, and its derived `WidgetCurrency` update target sources its id
            # from `cost.currency`, so a `Widget` with no `cost` both fails validation and breaks
            # building the operations we attach to the `FailedEventError`. Reporting the malformation
            # matters more than reporting operations we are never going to run, and
            # `FailedEventError#operations` is documented as sometimes being empty for this reason.
            let(:event) do
              build_upsert_event(:widget, id: "1", __version: 1).tap { |e| e["record"].delete("cost") }
            end

            it "still reports what was malformed instead of letting the second failure mask the first" do
              failure = indexer.operation_factory.build(event).failed_event_error

              expect(failure).to be_an(FailedEventError)
              expect(failure.operations).to be_empty
              expect(failure.main_message).to include("Malformed Widget record", "cost").and exclude("Key not found")
            end

            it "logs the failure it swallowed, so a discarded operation-building error is still traceable" do
              indexer.operation_factory.build(event)

              expect(logged_jsons_of_type("FailedEventOperationBuildingFailure")).to match([a_hash_including(
                "event_id" => "Widget:1@v1",
                "error_class" => "KeyError"
              )])
            end
          end

          # A factory whose record preparation fails for a reason record validation cannot detect: a
          # runtime metadata defect, standing in for any bug that is not about the data itself.
          def factory_whose_record_preparation_is_broken
            record_preparer = instance_double(RecordPreparer)

            allow(record_preparer).to receive(:prepare_for_index)
              .and_raise(::KeyError, 'key not found: "nameInIndex"')

            adapter = indexer.ingestion_adapters.first
            allow(adapter).to receive(:validate_event).and_wrap_original do |original, *args, **kwargs|
              original.call(*args, **kwargs).with(record_preparer: record_preparer)
            end

            indexer.operation_factory
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
              SCHEMA_VERSION_KEY => 1
            }.merge(latency_timestamps))])
          end

          it "notifies an error on unknown graphql type" do
            event = {
              "op" => "upsert",
              "id" => "1",
              "type" => "MyOwnInvalidGraphQlType",
              "version" => 1,
              SCHEMA_VERSION_KEY => 1,
              "record" => {"field1" => "value1", "field2" => "value2", "id" => "1"}
            }

            # We can't build any operations when the `type` is unknown. We don't know what index to target!
            expect_failed_event_error(event, "/properties/type", expect_no_ops: true)
          end

          it "notifies an error on a graphql type that is not ingestible" do
            event = {
              "op" => "upsert",
              "id" => "1",
              "type" => "WidgetOptions",
              "version" => 1,
              SCHEMA_VERSION_KEY => 1,
              "record" => {"field1" => "value1", "field2" => "value2", "id" => "1"}
            }

            expect(indexer.datastore_core.index_definitions_by_graphql_type.fetch(event.fetch("type"), [])).to be_empty

            # We can't build any operations when the `type` isn't an ingestible type
            expect_failed_event_error(event, "/properties/type", expect_no_ops: true)
          end

          it "notifies an error on missing type" do
            event = build_upsert_event(:component).except("type")

            # We can't build any operations when the `type` isn't in the event. We don't know what index to target!
            expect_failed_event_error(event, "missing_keys", "type", expect_no_ops: true)
          end

          it "notifies an error on missing `#{SCHEMA_VERSION_KEY}`" do
            event = build_upsert_event(:component).except(SCHEMA_VERSION_KEY)

            expect_failed_event_error(event, SCHEMA_VERSION_KEY)
          end

          it "notifies an error on wrong field types" do
            event = {
              "op" => "upsert",
              "id" => 1,
              SCHEMA_VERSION_KEY => 1,
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

          context "for an event of a non-indexed `sourced_from` source type", :json_ingestion_schema_definition do
            let(:indexer) do
              build_indexer(schema_definition: lambda do |s|
                s.object_type "Widget" do |t|
                  t.field "id", "ID!"
                  t.field "name", "String"
                  t.field "component_ids", "[ID!]!"
                end

                s.object_type "Component" do |t|
                  t.field "id", "ID!"
                  t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in, indexing_only: true

                  t.field "widget_name", "String" do |f|
                    f.sourced_from "widget", "name"
                  end

                  t.index "components" do |i|
                    i.has_had_multiple_sources!
                  end
                end
              end)
            end

            it "builds only the `sourced_from` update operations since the source type has no index of its own" do
              event = {
                "op" => "upsert",
                "id" => "w1",
                "type" => "Widget",
                "version" => 1,
                JSON_SCHEMA_VERSION_KEY => 1,
                "record" => {"id" => "w1", "name" => "Widgy", "component_ids" => ["c1", "c2"]}
              }

              operations = build_expecting_success(event)

              expect(operations.map { |op| op.update_target.type }).to all eq "Component"
              expect(operations.map(&:destination_index_def)).to all eq index_def_named("components")
              expect(operations.map(&:doc_id)).to contain_exactly("c1", "c2")
            end
          end

          context "when multiple ingestion adapters are available" do
            it "routes each event to the first adapter that recognizes it" do
              event = build_upsert_event(:component, id: "1", __version: 1)

              non_matching_adapter = instance_double(IngestionAdapter::Interface, handles_event?: false)
              matching_adapter = indexer.ingestion_adapters.first
              allow(matching_adapter).to receive(:validate_event).and_call_original

              factory = indexer.operation_factory.with(ingestion_adapters: [non_matching_adapter, matching_adapter])
              result = factory.build(event)

              expect(result.failed_event_error).to be nil
              expect(result.operations).not_to be_empty
              expect(matching_adapter).to have_received(:validate_event).with(a_hash_including("type" => "Component"), skip_record_validation: false)
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
