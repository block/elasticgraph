# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer"
require "elastic_graph/indexer/test_support/converters"
require "elastic_graph/indexer/processor"
require "elastic_graph/indexer/datastore_indexing_router"
require "elastic_graph/support/hash_util"
require "json"

module ElasticGraph
  class Indexer
    RSpec.describe Processor do
      describe ".process", :factories, :capture_logs do
        let(:clock) { class_double(Time, now: Time.iso8601("2020-09-15T12:30:00Z")) }
        let(:datastore_router) { instance_spy(ElasticGraph::Indexer::DatastoreIndexingRouter) }
        let(:component_to_ignore) { build_upsert_event(:component, id: ignored_event_id.id, __version: ignored_event_id.version) }
        let(:indexer) do
          build_indexer_with(
            latency_thresholds: {
              "originated_at" => 150_000,
              "touched_by_foo_at" => 200_000
            }
          )
        end

        before do
          allow(datastore_router).to receive(:bulk) do |ops, **options|
            ops_and_results = ops.map { |op| [op, Operation::Result.success_of(op)] }
            DatastoreIndexingRouter::BulkResult.new({"main" => ops_and_results})
          end

          allow(datastore_router).to receive(:source_event_versions_in_index) do |ops|
            ops.to_h do |op|
              [op, {"main" => []}]
            end
          end
        end

        it "calls router.bulk" do
          component = build_upsert_event(:component, id: "123", __version: 1)
          address = build_upsert_event(:address, id: "123", __version: 1)

          process([component, address])

          expect(datastore_router).to have_received(:bulk).with(
            [
              new_primary_indexing_operation(component.merge("record" => component["record"].merge("id" => component.fetch("id")))),
              new_primary_indexing_operation(address.merge("record" => address["record"].merge("id" => address.fetch("id"))))
            ],
            refresh: true
          )
        end

        context "when `router.bulk` returns some failures" do
          let(:component1) { build_upsert_event(:component, id: "c123", __version: 1) }
          let(:component2) { build_upsert_event(:component, id: "c234", __version: 1) }
          let(:component3) { build_upsert_event(:component, id: "c345", __version: 1) }

          before do
            allow(datastore_router).to receive(:bulk) do |ops, **options|
              expect(ops.map(&:event)).to eq([component1, component2, component3])

              DatastoreIndexingRouter::BulkResult.new({"main" => [
                [ops[0], Operation::Result.success_of(ops[0])],
                [ops[1], Operation::Result.failure_of(ops[1], "overloaded!")],
                [ops[2], Operation::Result.success_of(ops[2])]
              ]})
            end
          end

          it "raises `IndexingFailuresError` so the events can be retried later, while still logging what got processed successfully" do
            expect {
              process([component1, component2, component3])
            }.to raise_error(
              IndexingFailuresError,
              a_string_including(
                "Got 1 failure(s) from 3 event(s)", "update Component:c234@v1 failure--overloaded"
              ).and(excluding("c123", "c345"))
            )
          end

          it "allows the caller to handle the failures if they call `process_returning_failures` instead of `process`" do
            failures = process_returning_failures([component1, component2, component3])

            expect(failures).to all be_a FailedEventError
            expect(failures.map(&:id)).to contain_exactly("c234")
          end
        end

        describe "latency metrics" do
          it "extracts latency metrics from events" do
            component = upsert_event_with_latency_timestamps(:component, 36, 72)
            address = upsert_event_with_latency_timestamps(:address, 108, 144)

            process([component, address])

            expect(logged_jsons_of_type("ElasticGraphIndexingLatencies")).to match([
              a_hash_including(
                "event_type" => "Component",
                "latencies_in_ms_from" => {
                  "originated_at" => 36000,
                  "touched_by_foo_at" => 72000
                },
                "slo_results" => {
                  "originated_at" => "good",
                  "touched_by_foo_at" => "good"
                }
              ),
              a_hash_including(
                "event_type" => "Address",
                "latencies_in_ms_from" => {
                  "originated_at" => 108000,
                  "touched_by_foo_at" => 144000
                },
                "slo_results" => {
                  "originated_at" => "good",
                  "touched_by_foo_at" => "good"
                }
              )
            ])
          end

          it "fully identifies each event and message in the logged `ElasticGraphIndexingLatencies` message" do
            component = upsert_event_with_latency_timestamps(:component, 36, 72).merge("message_id" => "m1")
            process([component])

            expect(logged_jsons_of_type("ElasticGraphIndexingLatencies").first).to include(
              "event_id" => "Component:#{component.fetch("id")}@v#{component.fetch("version")}",
              "message_id" => "m1"
            )
          end

          it "avoids double-emitting metrics for multiple operations from the same event" do
            widget = upsert_event_with_latency_timestamps(:widget, 36, 72)

            process([widget])

            expect(logged_jsons_of_type("ElasticGraphIndexingLatencies")).to match([
              a_hash_including(
                "event_type" => "Widget",
                "latencies_in_ms_from" => {
                  "originated_at" => 36000,
                  "touched_by_foo_at" => 72000
                },
                "slo_results" => {
                  "originated_at" => "good",
                  "touched_by_foo_at" => "good"
                }
              )
            ])
          end

          it "emits latency metrics for all events, including those that did not update the datastore" do
            component1 = upsert_event_with_latency_timestamps(:component, 36, 72)
            address = upsert_event_with_latency_timestamps(:address, 108, 144)
            component2 = upsert_event_with_latency_timestamps(:component, 12, 24, id: "no_op_update")

            allow(datastore_router).to receive(:bulk) do |ops, **options|
              # simulate the update with id == `no_op_update` being an ignored event due to the version not increasing
              ops_and_results = ops.map do |op|
                result =
                  if op.event.fetch("id") == "no_op_update"
                    Operation::Result.noop_of(op, "was a noop")
                  else
                    Operation::Result.success_of(op)
                  end

                [op, result]
              end

              DatastoreIndexingRouter::BulkResult.new({"main" => ops_and_results})
            end

            process([component1, address, component2])

            expect(logged_jsons_of_type("ElasticGraphIndexingLatencies")).to match([
              a_hash_including(
                "event_type" => "Component",
                "latencies_in_ms_from" => {
                  "originated_at" => 36000,
                  "touched_by_foo_at" => 72000
                },
                "slo_results" => {
                  "originated_at" => "good",
                  "touched_by_foo_at" => "good"
                },
                "result" => "success"
              ),
              a_hash_including(
                "event_type" => "Address",
                "latencies_in_ms_from" => {
                  "originated_at" => 108000,
                  "touched_by_foo_at" => 144000
                },
                "slo_results" => {
                  "originated_at" => "good",
                  "touched_by_foo_at" => "good"
                },
                "result" => "success"
              ),
              a_hash_including(
                "event_type" => "Component",
                "latencies_in_ms_from" => {
                  "originated_at" => 12000,
                  "touched_by_foo_at" => 24000
                },
                "slo_results" => {
                  "originated_at" => "good",
                  "touched_by_foo_at" => "good"
                },
                "result" => "noop"
              )
            ])
          end

          it "logs true slo_results for events with latencies exceeding the configured thresholds" do
            # thresholds set in `let(:indexer)` are 150 and 200 seconds.
            no_outliers = upsert_event_with_latency_timestamps(:component, 36, 72, id: "good")
            originated_at_outlier = upsert_event_with_latency_timestamps(:component, 151, 72, id: "bad1", __version: 7)
            touched_by_foo_outlier = upsert_event_with_latency_timestamps(:component, 36, 201, id: "bad2", __version: 2)
            both_exact_outliers = upsert_event_with_latency_timestamps(:component, 150, 200, id: "bad_both", __version: 3)

            process([no_outliers, originated_at_outlier, touched_by_foo_outlier, both_exact_outliers])

            logged_jsons = logged_jsons_of_type("ElasticGraphIndexingLatencies")

            conditions = [
              {
                substring: "bad1@v7",
                expected: {
                  "originated_at" => "bad",
                  "touched_by_foo_at" => "good"
                }
              },
              {
                substring: "bad2@v2",
                expected: {
                  "touched_by_foo_at" => "bad",
                  "originated_at" => "good"
                }
              },
              {
                substring: "bad_both@v3",
                expected: {
                  "originated_at" => "bad",
                  "touched_by_foo_at" => "bad"
                }
              }
            ]

            conditions.each do |condition|
              expect(logged_jsons).to include(
                a_hash_including(
                  "event_id" => a_string_including(condition[:substring]),
                  "slo_results" => condition[:expected]
                )
              )
            end
          end

          it "omits timestamps from `slo_results` when they have no configured threshold" do
            no_outliers = upsert_event_with_latency_timestamps(:component, 36, 72, id: "good")
            originated_at_outlier = upsert_event_with_latency_timestamps(:component, 151, 72, id: "bad1", __version: 7)
            touched_by_foo_outlier = upsert_event_with_latency_timestamps(:component, 36, 201, id: "bad2", __version: 2)
            both_exact_outliers = upsert_event_with_latency_timestamps(:component, 150, 200, id: "bad_both", __version: 3)

            indexer = build_indexer_with(latency_thresholds: {
              "originated_at" => 150_000
            })

            indexer.processor.process([no_outliers, originated_at_outlier, touched_by_foo_outlier, both_exact_outliers], refresh_indices: true)

            logged_jsons = logged_jsons_of_type("ElasticGraphIndexingLatencies")

            conditions = [
              {
                substring: "bad1@v7",
                expected: {
                  "originated_at" => "bad"
                }
              },
              {
                substring: "bad2@v2",
                expected: {
                  "originated_at" => "good"
                }
              },
              {
                substring: "bad_both@v3",
                expected: {
                  "originated_at" => "bad"
                }
              }
            ]

            conditions.each do |condition|
              expect(logged_jsons).to include(
                a_hash_including(
                  "event_id" => a_string_including(condition[:substring]),
                  "slo_results" => condition[:expected]
                )
              )
            end
          end

          def upsert_event_with_latency_timestamps(entity_type, originated_at_offset, touched_by_foo_at_offset, **options)
            build_upsert_event(entity_type, **options).merge({
              "latency_timestamps" => {
                "originated_at" => (clock.now - originated_at_offset).iso8601,
                "touched_by_foo_at" => (clock.now - touched_by_foo_at_offset).iso8601
              }
            })
          end
        end

        context "when the list of events includes some invalid ones" do
          let(:good_component) { build_upsert_event(:component, id: "123", __version: 1) }
          let(:good_address) { build_upsert_event(:address, id: "456", __version: 1) }

          let(:events) do
            [
              good_component,
              make_component_bad(good_component).merge("id" => "234"),
              good_address,
              good_address.merge("type" => "Color", "id" => "345") # Color is not a valid `type`
            ]
          end

          it "allows the valid events to be written, raising an error describing the invalid events" do
            expect {
              process(events)
            }.to raise_error IndexingFailuresError, a_string_including(
              "2 failure(s) from 4 event(s)",
              "1) Component:234@v1: Malformed Component record",
              "2) Color:345@v1: Malformed event payload"
            )

            expect(datastore_router).to have_received(:bulk).with(
              [
                new_primary_indexing_operation(good_component),
                new_primary_indexing_operation(good_address)
              ],
              refresh: true
            )
          end

          it "mentions the `message_id` in the exception message if its available" do
            expect {
              events_with_msg_ids = events.map.with_index(1) { |e, index| e.merge("message_id" => "m#{index}") }
              process(events_with_msg_ids)
            }.to raise_error IndexingFailuresError, a_string_including(
              "2 failure(s) from 4 event(s)",
              "1) Component:234@v1 (message_id: m2): Malformed Component record",
              "2) Color:345@v1 (message_id: m4): Malformed event payload"
            )
          end

          it "allows the caller to handle the failures if they call `process_returning_failures` instead of `process`" do
            failures = process_returning_failures(events)

            expect(failures).to all be_a FailedEventError
            expect(failures.map(&:id)).to contain_exactly("234", "345")

            expect(datastore_router).to have_received(:bulk).with(
              [
                new_primary_indexing_operation(good_component),
                new_primary_indexing_operation(good_address)
              ],
              refresh: true
            )
          end

          def make_component_bad(component)
            component.merge("record" => component["record"].merge(
              "name" => 17 # must be an string
            ))
          end
        end

        def new_primary_indexing_operation(event)
          update_targets = indexer
            .schema_artifacts
            .runtime_metadata
            .object_types_by_name
            .fetch(event.fetch("type"))
            .update_targets
            .select { |ut| ut.type == event.fetch("type") }

          expect(update_targets.size).to eq(1)

          index_name = {
            "Component" => "components",
            "Address" => "addresses"
          }.fetch(event.fetch("type"))

          index_def = indexer.datastore_core.index_definitions_by_name.fetch(index_name)

          Operation::Update.new(
            event: event,
            prepared_record: indexer.record_preparer_factory.for_latest_json_schema_version.prepare_for_index(
              event.fetch("type"),
              event.fetch("record")
            ),
            destination_index_def: index_def,
            update_target: update_targets.first,
            doc_id: event.fetch("id"),
            destination_index_mapping: indexer.schema_artifacts.index_mappings_by_index_def_name.fetch(index_def.name)
          )
        end

        def build_indexer_with(latency_thresholds:)
          build_indexer(
            clock: clock,
            datastore_router: datastore_router,
            latency_slo_thresholds_by_timestamp_in_ms: latency_thresholds
          )
        end

        def process(*events)
          indexer.processor.process(*events, refresh_indices: true)
        end

        def process_returning_failures(*events)
          indexer.processor.process_returning_failures(*events, refresh_indices: true)
        end
      end
    end
  end
end
