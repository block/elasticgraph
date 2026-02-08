# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer"
require "elastic_graph/indexer/operation/update"
require "elastic_graph/indexer/operation/coalesced_update"
require "elastic_graph/spec_support/runtime_metadata_support"
require "json"

module ElasticGraph
  class Indexer
    module Operation
      RSpec.describe CoalescedUpdate do
        include SchemaArtifacts::RuntimeMetadata::RuntimeMetadataSupport

        let(:update_target) do
          derived_indexing_update_target_with(
            type: "OrderMerchant",
            script_id: "update_OrderMerchant_from_Order_abc123"
          )
        end

        let(:event1) do
          {
            "op" => "upsert",
            "id" => "order_1",
            "type" => "Order",
            "version" => 1,
            "record" => {"merchant_id" => "m1", "created_at" => "2026-01-01T00:00:00Z"}
          }
        end

        let(:event2) do
          {
            "op" => "upsert",
            "id" => "order_2",
            "type" => "Order",
            "version" => 2,
            "record" => {"merchant_id" => "m1", "created_at" => "2026-01-02T00:00:00Z"}
          }
        end

        let(:event3) do
          {
            "op" => "upsert",
            "id" => "order_3",
            "type" => "Order",
            "version" => 3,
            "record" => {"merchant_id" => "m1", "created_at" => "2026-01-03T00:00:00Z"}
          }
        end

        def make_update(event, doc_id: "m1")
          Update.new(
            event: event,
            prepared_record: event["record"],
            destination_index_def: nil,
            update_target: update_target,
            doc_id: doc_id,
            destination_index_mapping: {}
          )
        end

        describe "#type" do
          it "returns :update" do
            coalesced = CoalescedUpdate.new([make_update(event1)])
            expect(coalesced.type).to eq(:update)
          end
        end

        describe "#versioned?" do
          it "returns false since derived updates are never versioned" do
            coalesced = CoalescedUpdate.new([make_update(event1)])
            expect(coalesced.versioned?).to be false
          end
        end

        describe "#event" do
          it "delegates to the first source operation" do
            coalesced = CoalescedUpdate.new([make_update(event1), make_update(event2)])
            expect(coalesced.event).to eq(event1)
          end
        end

        describe "#all_events" do
          it "returns events from all source operations" do
            coalesced = CoalescedUpdate.new([make_update(event1), make_update(event2), make_update(event3)])
            expect(coalesced.all_events).to eq([event1, event2, event3])
          end
        end

        describe "#source_operations" do
          it "returns all source operations" do
            ops = [make_update(event1), make_update(event2), make_update(event3)]
            coalesced = CoalescedUpdate.new(ops)
            expect(coalesced.source_operations).to eq(ops)
          end
        end

        describe "#doc_id" do
          it "returns the shared doc_id from the source operations" do
            coalesced = CoalescedUpdate.new([make_update(event1, doc_id: "merchant_abc")])
            expect(coalesced.doc_id).to eq("merchant_abc")
          end
        end

        describe "#description" do
          it "includes the type and count of coalesced events" do
            ops = [make_update(event1), make_update(event2), make_update(event3)]
            coalesced = CoalescedUpdate.new(ops)
            expect(coalesced.description).to eq("OrderMerchant coalesced update (3 events)")
          end
        end

        describe "#inspect" do
          it "provides a readable representation" do
            ops = [make_update(event1), make_update(event2)]
            coalesced = CoalescedUpdate.new(ops)
            expect(coalesced.inspect).to include("CoalescedUpdate", "doc_id=m1", "OrderMerchant", "ops=2")
            expect(coalesced.to_s).to eq(coalesced.inspect)
          end
        end

        describe "#to_datastore_bulk" do
          let(:update_target_with_params) do
            derived_indexing_update_target_with(
              type: "OrderMerchant",
              script_id: "update_OrderMerchant_from_Order_abc123",
              data_params: {
                "createdAt" => dynamic_param_with(source_path: "created_at", cardinality: :many),
                "isTest" => dynamic_param_with(source_path: "is_test", cardinality: :many)
              }
            )
          end

          let(:destination_index_def) do
            instance_double(
              "ElasticGraph::DatastoreCore::IndexDefinition::Index",
              name: "order_merchants",
              index_name_for_writes: "order_merchants",
              routing_value_for_prepared_record: nil
            )
          end

          def make_update_with_params(event, doc_id: "m1")
            Update.new(
              event: event,
              prepared_record: event["record"],
              destination_index_def: destination_index_def,
              update_target: update_target_with_params,
              doc_id: doc_id,
              destination_index_mapping: {}
            )
          end

          let(:event_a) do
            {
              "op" => "upsert", "id" => "o1", "type" => "Order", "version" => 1,
              "record" => {"merchant_id" => "m1", "created_at" => "2026-01-01T00:00:00Z", "is_test" => false}
            }
          end

          let(:event_b) do
            {
              "op" => "upsert", "id" => "o2", "type" => "Order", "version" => 2,
              "record" => {"merchant_id" => "m1", "created_at" => "2026-02-01T00:00:00Z", "is_test" => false}
            }
          end

          let(:event_c) do
            {
              "op" => "upsert", "id" => "o3", "type" => "Order", "version" => 3,
              "record" => {"merchant_id" => "m1", "created_at" => "2026-03-01T00:00:00Z", "is_test" => true}
            }
          end

          it "merges data params by concatenating value lists from all source operations" do
            ops = [make_update_with_params(event_a), make_update_with_params(event_b), make_update_with_params(event_c)]
            coalesced = CoalescedUpdate.new(ops)

            _metadata, request = coalesced.to_datastore_bulk
            merged_data = request[:script][:params]["data"]

            expect(merged_data["createdAt"]).to eq(["2026-01-01T00:00:00Z", "2026-02-01T00:00:00Z", "2026-03-01T00:00:00Z"])
            expect(merged_data["isTest"]).to eq([false, false, true])
          end

          it "uses the correct script_id" do
            ops = [make_update_with_params(event_a), make_update_with_params(event_b)]
            coalesced = CoalescedUpdate.new(ops)

            _metadata, request = coalesced.to_datastore_bulk
            expect(request[:script][:id]).to eq("update_OrderMerchant_from_Order_abc123")
          end

          it "uses scripted_upsert with an empty upsert document" do
            ops = [make_update_with_params(event_a), make_update_with_params(event_b)]
            coalesced = CoalescedUpdate.new(ops)

            _metadata, request = coalesced.to_datastore_bulk
            expect(request[:scripted_upsert]).to be true
            expect(request[:upsert]).to eq({})
          end

          it "preserves the doc_id in merged params" do
            ops = [make_update_with_params(event_a), make_update_with_params(event_b)]
            coalesced = CoalescedUpdate.new(ops)

            _metadata, request = coalesced.to_datastore_bulk
            expect(request[:script][:params]["id"]).to eq("m1")
          end

          it "memoizes the result" do
            ops = [make_update_with_params(event_a), make_update_with_params(event_b)]
            coalesced = CoalescedUpdate.new(ops)

            expect(coalesced.to_datastore_bulk).to equal(coalesced.to_datastore_bulk)
          end
        end

        describe "#categorize" do
          let(:operations) { [make_update(event1), make_update(event2)] }
          let(:coalesced) { CoalescedUpdate.new(operations) }

          it "categorizes a 2xx response as :success" do
            response = {"update" => {"status" => 200}}
            result = coalesced.categorize(response)

            expect(result.category).to eq(:success)
            expect(result.operation).to eq(coalesced)
          end

          it "categorizes a noop result as :noop" do
            response = {"update" => {"status" => 200, "result" => "noop"}}
            result = coalesced.categorize(response)

            expect(result.category).to eq(:noop)
          end

          it "categorizes a response as :noop when the script throws the noop preamble" do
            response = {"update" => {"status" => 500, "error" => {
              "reason" => "an exception was thrown",
              "caused_by" => {"caused_by" => {
                "reason" => "#{UPDATE_WAS_NOOP_MESSAGE_PREAMBLE}the version was too low"
              }}
            }}}

            result = coalesced.categorize(response)

            expect(result.category).to eq(:noop)
            expect(result.description).to eq("the version was too low")
          end

          it "categorizes non-2xx, non-noop responses as :failure" do
            response = {"update" => {"status" => 500, "error" => {
              "reason" => "script error",
              "caused_by" => {"caused_by" => {"type" => "illegal_argument_exception", "reason" => "field cannot be changed"}}
            }}}

            result = coalesced.categorize(response)

            expect(result.category).to eq(:failure)
            expect(result.description).to include("update_OrderMerchant_from_Order_abc123")
            expect(result.description).to include("applied to `m1`")
            expect(result.description).to include("field cannot be changed")
          end
        end
      end
    end
  end
end
