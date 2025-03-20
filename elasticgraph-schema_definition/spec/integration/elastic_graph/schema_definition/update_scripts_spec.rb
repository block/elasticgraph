# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/runtime_metadata_support"
require "support/script_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "Update scripts" do
      include SchemaArtifacts::RuntimeMetadata::RuntimeMetadataSupport

      describe "for a derived indexing type" do
        include_context "widget currency script support", expected_function_defs: [
          Indexing::DerivedFields::AppendOnlySet::IDEMPOTENTLY_INSERT_VALUE,
          Indexing::DerivedFields::AppendOnlySet::IDEMPOTENTLY_INSERT_VALUES,
          Indexing::DerivedFields::ImmutableValue::IDEMPOTENTLY_SET_VALUE,
          Indexing::DerivedFields::MinOrMaxValue.function_def(:max),
          Indexing::DerivedFields::MinOrMaxValue.function_def(:min)
        ]

        it "produces none when the `derive_indexed_type_fields` is not used in the schema definition" do
          script_id, payload, update_target = script_artifacts_for_widget_currency_from "Widget" do |t|
            t.field "id", "ID"
            t.index "widgets"
          end

          expect(script_id).to eq nil
          expect(payload).to eq nil
          expect(update_target).to eq nil
        end

        it "fails with a clear error when no derived fields are defined" do
          expect {
            script_artifacts_for_widget_currency_from "Widget" do |t|
              t.field "id", "ID"
              t.index "widgets"

              t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("derive_indexed_type_fields", "Widget", "WidgetCurrency")
        end

        it "produces a script when `derive_indexed_type_fields` is used with each type of derived field at the same time" do
          script_id, payload, update_target = script_artifacts_for_widget_currency_from "Widget" do |t|
            t.field "id", "ID"
            t.index "widgets"

            t.derive_indexed_type_fields(
              "WidgetCurrency",
              from_id: "cost.currency",
              route_with: "cost_currency_name",
              rollover_with: "currency_introduced_on"
            ) do |derive|
              derive.append_only_set "workspace_ids", from: "workspace_id"
              derive.immutable_value "name", from: "cost_currency_name"
              derive.min_value "oldest_widget_created_at", from: "created_at"
              derive.max_value "newest_widget_created_at", from: "created_at"
            end
          end

          expect_widget_currency_script(script_id, payload, <<~EOS.strip)
            if (ctx._source.workspace_ids == null) {
              ctx._source.workspace_ids = [];
            }

            boolean name_was_noop = !immutableValue_idempotentlyUpdateValue(scriptErrors, data["cost_currency_name"], ctx._source, "name", "name", true, false);
            boolean newest_widget_created_at_was_noop = !maxValue_idempotentlyUpdateValue(data["created_at"], ctx._source, "newest_widget_created_at");
            boolean oldest_widget_created_at_was_noop = !minValue_idempotentlyUpdateValue(data["created_at"], ctx._source, "oldest_widget_created_at");
            boolean workspace_ids_was_noop = !appendOnlySet_idempotentlyInsertValues(data["workspace_id"], ctx._source.workspace_ids);

            if (!scriptErrors.isEmpty()) {
              throw new IllegalArgumentException("#{DERIVED_INDEX_FAILURE_MESSAGE_PREAMBLE}: " + scriptErrors.join(" "));
            }

            // For records with no new values to index, only skip the update if the document itself doesn't already exist.
            // Otherwise create an (empty) document to reflect the fact that the id has been seen.
            if (ctx._source.id != null && name_was_noop && newest_widget_created_at_was_noop && oldest_widget_created_at_was_noop && workspace_ids_was_noop) {
              ctx.op = 'none';
            } else {
              // Here we set `_source.id` because if we don't, it'll never be set, making these docs subtly
              // different from docs indexed the normal way.
              //
              // Note also that we MUST use `params.id` instead of `ctx._id`. The latter works on an update
              // of an existing document, but is unavailable when we are inserting the document for the first time.
              ctx._source.id = params.id;
            }
          EOS

          expect(update_target).to eq(derived_indexing_update_target_with(
            type: "WidgetCurrency",
            script_id: script_id,
            id_source: "cost.currency",
            routing_value_source: "cost_currency_name",
            rollover_timestamp_value_source: "currency_introduced_on",
            data_params: {
              "workspace_id" => dynamic_param_with(source_path: "workspace_id", cardinality: :many),
              "cost_currency_name" => dynamic_param_with(source_path: "cost_currency_name", cardinality: :many),
              "created_at" => dynamic_param_with(source_path: "created_at", cardinality: :many)
            }
          ))
        end
      end
    end
  end
end
