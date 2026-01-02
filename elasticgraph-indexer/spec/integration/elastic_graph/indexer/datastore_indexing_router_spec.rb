# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/datastore_indexing_router"
require "elastic_graph/support/monotonic_clock"

module ElasticGraph
  class Indexer
    RSpec.describe DatastoreIndexingRouter, :uses_datastore, :capture_logs do
      describe "#source_event_versions_in_index", :factories do
        let(:indexer) { build_indexer }
        let(:router) { indexer.datastore_router }
        let(:operation_factory) { indexer.operation_factory }

        it "looks up the document version for each of the specified operations, returning a map of versions by operation" do
          test_documents_of_type(:address) do |op|
            expect(uses_custom_routing?(op)).to eq false
          end
        end

        it "queries the version from the correct shard when the index uses custom shard routing" do
          test_documents_of_type(:widget) do |op|
            expect(uses_custom_routing?(op)).to eq true
          end
        end

        it "returns an empty list of versions when only given an unversioned operation" do
          unversioned_op = build_expecting_success(build_upsert_event(:widget)).find { |op| !op.versioned? }
          expect(unversioned_op).to be_a(Operation::Update)

          expect {
            versions_by_cluster_by_op = router.source_event_versions_in_index([unversioned_op])

            expect(versions_by_cluster_by_op).to eq({unversioned_op => {"main" => []}})
          }.not_to change { datastore_requests("main") }
        end

        it "finds the document on any shard, even if it differs from what the operation's routing key would route to" do
          op1 = build_primary_indexing_op(:widget, id: "mutated_routing_key", workspace_id: "wid1")

          results = router.bulk([op1], refresh: true)
          expect(results.successful_operations_by_cluster_name).to match("main" => a_collection_containing_exactly(op1))

          op2 = build_primary_indexing_op(:widget, id: "mutated_routing_key", workspace_id: "wid2")
          versions_by_cluster_by_op = router.source_event_versions_in_index([op2])

          expect(versions_by_cluster_by_op.keys).to contain_exactly(op2)
          expect(versions_by_cluster_by_op[op2]).to eq("main" => [op1.event.fetch("version")])
        end

        it "finds the document on any index, even if it differs from the operation's target index" do
          op1 = build_primary_indexing_op(:widget, id: "mutated_rollover_timestamp", created_at: "2019-12-03T00:00:00Z")

          results = router.bulk([op1], refresh: true)
          expect(results.successful_operations_by_cluster_name).to match("main" => a_collection_containing_exactly(op1))

          op2 = build_primary_indexing_op(:widget, id: "mutated_rollover_timestamp", created_at: "2023-12-03T00:00:00Z")
          versions_by_cluster_by_op = router.source_event_versions_in_index([op2])

          expect(versions_by_cluster_by_op.keys).to contain_exactly(op2)
          expect(versions_by_cluster_by_op[op2]).to eq("main" => [op1.event.fetch("version")])
        end

        it "logs a warning and returns all versions if multiple copies of the document are found" do
          op1 = build_primary_indexing_op(:widget, id: "mutated_routing_and_timestamp", workspace_id: "wid1", created_at: "2019-12-03T00:00:00Z")
          op2 = build_primary_indexing_op(:widget, id: "mutated_routing_and_timestamp", workspace_id: "wid2", created_at: "2023-12-03T00:00:00Z", __version: op1.event.fetch("version") + 1)

          results = router.bulk([op1, op2], refresh: true)
          expect(results.successful_operations_by_cluster_name).to match("main" => a_collection_containing_exactly(op1, op2))

          expect {
            versions_by_cluster_by_op = router.source_event_versions_in_index([op1])
            expect(versions_by_cluster_by_op.keys).to contain_exactly(op1)
            expect(versions_by_cluster_by_op[op1]).to match("main" => a_collection_containing_exactly(
              op1.event.fetch("version"),
              op2.event.fetch("version")
            ))

            versions_by_cluster_by_op = router.source_event_versions_in_index([op2])
            expect(versions_by_cluster_by_op.keys).to contain_exactly(op2)
            expect(versions_by_cluster_by_op[op2]).to match("main" => a_collection_containing_exactly(
              op1.event.fetch("version"),
              op2.event.fetch("version")
            ))
          }.to log_warning a_string_including("IdentifyDocumentVersionsGotMultipleResults")

          expect(logged_jsons_of_type("IdentifyDocumentVersionsGotMultipleResults")).to contain_exactly(
            a_hash_including(
              "id" => ["mutated_routing_and_timestamp", "mutated_routing_and_timestamp"],
              "routing" => a_collection_containing_exactly("wid1", "wid2"),
              "index" => a_collection_containing_exactly("widgets_rollover__after_2021", "widgets_rollover__2019")
            ),
            a_hash_including(
              "id" => ["mutated_routing_and_timestamp", "mutated_routing_and_timestamp"],
              "routing" => a_collection_containing_exactly("wid1", "wid2"),
              "index" => a_collection_containing_exactly("widgets_rollover__after_2021", "widgets_rollover__2019")
            )
          )
        end

        it "supports both primary indexing operations and derived indexing operations" do
          derived_update, self_update = build_expecting_success(build_upsert_event(:widget))
          expect(derived_update.update_target.type).to eq("WidgetCurrency")
          expect(self_update.update_target.type).to eq("Widget")

          results = router.bulk([derived_update, self_update], refresh: true)
          expect(results.successful_operations_by_cluster_name).to match("main" => a_collection_containing_exactly(derived_update, self_update))

          versions_by_cluster_by_op = router.source_event_versions_in_index([derived_update, self_update])
          expect(versions_by_cluster_by_op.keys).to contain_exactly(derived_update, self_update)
          expect(versions_by_cluster_by_op[self_update]).to eq("main" => [derived_update.event.fetch("version")])

          # The derived document doesn't keep track of `__versions` so it doesn't have a version it can return.
          expect(versions_by_cluster_by_op[derived_update]).to eq("main" => [])
        end

        def uses_custom_routing?(op)
          op.to_datastore_bulk.first.fetch(:update).key?(:routing)
        end

        def build_primary_indexing_op(type, **overrides)
          event = build_upsert_event(type, **overrides)
          ops = build_expecting_success(event).select { |op| op.update_target.for_normal_indexing? }
          expect(ops.size).to eq(1)
          ops.first
        end

        def test_documents_of_type(type, &block)
          op1 = build_primary_indexing_op(type).tap(&block)
          op2 = build_primary_indexing_op(type).tap(&block)
          op3 = build_primary_indexing_op(type).tap(&block)

          results = router.bulk([op1, op2], refresh: true)

          expect(results.successful_operations_by_cluster_name).to match("main" => a_collection_containing_exactly(op1, op2))

          versions_by_cluster_by_op = router.source_event_versions_in_index([])
          expect(versions_by_cluster_by_op).to eq({})

          versions_by_cluster_by_op = router.source_event_versions_in_index([op1, op2, op3])
          expect(versions_by_cluster_by_op.keys).to contain_exactly(op1, op2, op3)
          expect(versions_by_cluster_by_op[op1]).to eq("main" => [op1.event.fetch("version")])
          expect(versions_by_cluster_by_op[op2]).to eq("main" => [op2.event.fetch("version")])
          expect(versions_by_cluster_by_op[op3]).to eq("main" => [])
        end

        def build_expecting_success(event, **options)
          result = operation_factory.build(event, **options)
          # :nocov: -- our norm is to have no failure
          raise result.failed_event_error if result.failed_event_error
          # :nocov:
          result.operations
        end
      end
    end
  end
end
