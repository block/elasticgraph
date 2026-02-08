# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/derived_update_coalescer"
require "elastic_graph/indexer/operation/update"
require "elastic_graph/spec_support/runtime_metadata_support"

module ElasticGraph
  class Indexer
    RSpec.describe DerivedUpdateCoalescer do
      include SchemaArtifacts::RuntimeMetadata::RuntimeMetadataSupport

      let(:datastore_scripts) do
        {
          "safe_derived_script" => {
            "script" => {
              "source" => "appendOnlySet_idempotentlyInsertValues(data[\"name\"], ctx._source.widget_names);"
            }
          },
          "immutable_derived_script" => {
            "script" => {
              "source" => "immutableValue_idempotentlyUpdateValue(scriptErrors, data[\"name\"], ctx._source, \"name\", \"name\", true, false);"
            }
          }
        }
      end

      let(:safe_update_target) do
        derived_indexing_update_target_with(type: "OrderMerchant", script_id: "safe_derived_script")
      end

      let(:immutable_update_target) do
        derived_indexing_update_target_with(type: "OrderMerchant", script_id: "immutable_derived_script")
      end

      describe "#coalesce" do
        it "coalesces derived updates when script id, doc id, index, and routing are all the same" do
          op1 = build_derived_update("order_1", safe_update_target, routing: "merchant_1", write_index: "order_merchants__2026")
          op2 = build_derived_update("order_2", safe_update_target, routing: "merchant_1", write_index: "order_merchants__2026")

          coalescer = DerivedUpdateCoalescer.new(datastore_scripts)
          coalesced_operations = coalescer.coalesce([op1, op2])

          expect(coalesced_operations.size).to eq(1)
          expect(coalesced_operations.first).to be_a(Operation::CoalescedUpdate)
        end

        it "does not coalesce derived updates that target different routing values" do
          op1 = build_derived_update("order_1", safe_update_target, routing: "merchant_1", write_index: "order_merchants__2026")
          op2 = build_derived_update("order_2", safe_update_target, routing: "merchant_2", write_index: "order_merchants__2026")

          coalescer = DerivedUpdateCoalescer.new(datastore_scripts)
          coalesced_operations = coalescer.coalesce([op1, op2])

          expect(coalesced_operations).to contain_exactly(op1, op2)
        end

        it "does not coalesce derived updates that target different rollover indexes" do
          op1 = build_derived_update("order_1", safe_update_target, routing: "merchant_1", write_index: "order_merchants__2025")
          op2 = build_derived_update("order_2", safe_update_target, routing: "merchant_1", write_index: "order_merchants__2026")

          coalescer = DerivedUpdateCoalescer.new(datastore_scripts)
          coalesced_operations = coalescer.coalesce([op1, op2])

          expect(coalesced_operations).to contain_exactly(op1, op2)
        end

        it "does not coalesce scripts that use immutable value semantics" do
          op1 = build_derived_update("order_1", immutable_update_target, routing: "merchant_1", write_index: "order_merchants__2026")
          op2 = build_derived_update("order_2", immutable_update_target, routing: "merchant_1", write_index: "order_merchants__2026")

          coalescer = DerivedUpdateCoalescer.new(datastore_scripts)
          coalesced_operations = coalescer.coalesce([op1, op2])

          expect(coalesced_operations).to contain_exactly(op1, op2)
        end
      end

      def build_derived_update(order_id, update_target, routing:, write_index:)
        destination_index_def = instance_double(
          "ElasticGraph::DatastoreCore::IndexDefinition::Index",
          name: "order_merchants",
          index_name_for_writes: write_index,
          routing_value_for_prepared_record: routing
        )

        event = {
          "op" => "upsert",
          "type" => "Order",
          "id" => order_id,
          "version" => 1,
          "record" => {"merchant_id" => "merchant_1"}
        }

        Operation::Update.new(
          event: event,
          prepared_record: event.fetch("record"),
          destination_index_def: destination_index_def,
          update_target: update_target,
          doc_id: "merchant_1",
          destination_index_mapping: {}
        )
      end
    end
  end
end
