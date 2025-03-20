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
    RSpec.describe "Update scripts for append only set fields" do
      include SchemaArtifacts::RuntimeMetadata::RuntimeMetadataSupport

      include_context "widget currency script support", expected_function_defs: [
        Indexing::DerivedFields::AppendOnlySet::IDEMPOTENTLY_INSERT_VALUE,
        Indexing::DerivedFields::AppendOnlySet::IDEMPOTENTLY_INSERT_VALUES
      ]

      it "produces a script when `derive_indexed_type_fields` is used with a single append only set field" do
        script_id, payload, update_target = script_artifacts_for_widget_currency_from "Widget" do |t|
          t.field "id", "ID"
          t.index "widgets"

          t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
            derive.append_only_set "workspace_ids", from: "workspace_id"
          end
        end

        expect_widget_currency_script(script_id, payload, <<~EOS.strip)
          if (ctx._source.workspace_ids == null) {
            ctx._source.workspace_ids = [];
          }

          boolean workspace_ids_was_noop = !appendOnlySet_idempotentlyInsertValues(data["workspace_id"], ctx._source.workspace_ids);

          if (!scriptErrors.isEmpty()) {
            throw new IllegalArgumentException("Derived index update failed due to bad input data: " + scriptErrors.join(" "));
          }

          // For records with no new values to index, only skip the update if the document itself doesn't already exist.
          // Otherwise create an (empty) document to reflect the fact that the id has been seen.
          if (ctx._source.id != null && workspace_ids_was_noop) {
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
          routing_value_source: nil,
          rollover_timestamp_value_source: nil,
          data_params: {"workspace_id" => dynamic_param_with(source_path: "workspace_id", cardinality: :many)}
        ))
      end

      it "produces a script when `derive_indexed_type_fields` is used with multiple append only set fields" do
        script_id, payload, update_target = script_artifacts_for_widget_currency_from "Widget" do |t|
          t.field "id", "ID"
          t.index "widgets"

          t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
            derive.append_only_set "workspace_ids", from: "workspace_id"
            derive.append_only_set "sizes", from: "options.size"
            derive.append_only_set "colors", from: "options.color"
          end
        end

        expect_widget_currency_script(script_id, payload, <<~EOS.strip)
          if (ctx._source.colors == null) {
            ctx._source.colors = [];
          }
          if (ctx._source.sizes == null) {
            ctx._source.sizes = [];
          }
          if (ctx._source.workspace_ids == null) {
            ctx._source.workspace_ids = [];
          }

          boolean colors_was_noop = !appendOnlySet_idempotentlyInsertValues(data["options.color"], ctx._source.colors);
          boolean sizes_was_noop = !appendOnlySet_idempotentlyInsertValues(data["options.size"], ctx._source.sizes);
          boolean workspace_ids_was_noop = !appendOnlySet_idempotentlyInsertValues(data["workspace_id"], ctx._source.workspace_ids);

          if (!scriptErrors.isEmpty()) {
            throw new IllegalArgumentException("Derived index update failed due to bad input data: " + scriptErrors.join(" "));
          }

          // For records with no new values to index, only skip the update if the document itself doesn't already exist.
          // Otherwise create an (empty) document to reflect the fact that the id has been seen.
          if (ctx._source.id != null && colors_was_noop && sizes_was_noop && workspace_ids_was_noop) {
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
          routing_value_source: nil,
          rollover_timestamp_value_source: nil,
          data_params: {
            "workspace_id" => dynamic_param_with(source_path: "workspace_id", cardinality: :many),
            "options.size" => dynamic_param_with(source_path: "options.size", cardinality: :many),
            "options.color" => dynamic_param_with(source_path: "options.color", cardinality: :many)
          }
        ))
      end

      context "with a nested destination field" do
        it "defaults the parents of the nested field to an empty object, but avoids duplicating that initialization when one parent field has multiple derived subfields" do
          script_id, payload, update_target = script_artifacts_for_widget_currency_from "Widget" do |t|
            t.field "id", "ID"
            t.index "widgets"

            t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
              derive.append_only_set "widget_options.colors", from: "options.color"
              derive.append_only_set "widget_options.sizes", from: "options.size"
            end
          end

          expect_widget_currency_script(script_id, payload, <<~EOS.strip)
            if (ctx._source.widget_options == null) {
              ctx._source.widget_options = [:];
            }
            if (ctx._source.widget_options.colors == null) {
              ctx._source.widget_options.colors = [];
            }
            if (ctx._source.widget_options.sizes == null) {
              ctx._source.widget_options.sizes = [];
            }

            boolean widget_options__colors_was_noop = !appendOnlySet_idempotentlyInsertValues(data["options.color"], ctx._source.widget_options.colors);
            boolean widget_options__sizes_was_noop = !appendOnlySet_idempotentlyInsertValues(data["options.size"], ctx._source.widget_options.sizes);

            if (!scriptErrors.isEmpty()) {
              throw new IllegalArgumentException("Derived index update failed due to bad input data: " + scriptErrors.join(" "));
            }

            // For records with no new values to index, only skip the update if the document itself doesn't already exist.
            // Otherwise create an (empty) document to reflect the fact that the id has been seen.
            if (ctx._source.id != null && widget_options__colors_was_noop && widget_options__sizes_was_noop) {
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
            routing_value_source: nil,
            rollover_timestamp_value_source: nil,
            data_params: {
              "options.size" => dynamic_param_with(source_path: "options.size", cardinality: :many),
              "options.color" => dynamic_param_with(source_path: "options.color", cardinality: :many)
            }
          ))
        end
      end
    end
  end
end
