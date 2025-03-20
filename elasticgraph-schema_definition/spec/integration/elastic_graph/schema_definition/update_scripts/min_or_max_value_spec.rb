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
    RSpec.describe "Update scripts for `min_value`/`max_value` fields" do
      include SchemaArtifacts::RuntimeMetadata::RuntimeMetadataSupport

      context "for just a `max_value` field" do
        include_context "widget currency script support", expected_function_defs: [
          Indexing::DerivedFields::MinOrMaxValue.function_def(:max)
        ]

        it "produces a script when `derive_indexed_type_fields` is used with a single max value field" do
          script_id, payload, update_target = script_artifacts_for_widget_currency_from "Widget" do |t|
            t.field "id", "ID"
            t.index "widgets"

            t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
              derive.max_value "newest_widget_created_at", from: "created_at"
            end
          end

          expect_widget_currency_script(script_id, payload, <<~EOS.chomp)

            boolean newest_widget_created_at_was_noop = !maxValue_idempotentlyUpdateValue(data["created_at"], ctx._source, "newest_widget_created_at");

            if (!scriptErrors.isEmpty()) {
              throw new IllegalArgumentException("#{DERIVED_INDEX_FAILURE_MESSAGE_PREAMBLE}: " + scriptErrors.join(" "));
            }

            // For records with no new values to index, only skip the update if the document itself doesn't already exist.
            // Otherwise create an (empty) document to reflect the fact that the id has been seen.
            if (ctx._source.id != null && newest_widget_created_at_was_noop) {
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
            data_params: {"created_at" => dynamic_param_with(source_path: "created_at", cardinality: :many)}
          ))
        end
      end

      context "for just a `min_value` field" do
        include_context "widget currency script support", expected_function_defs: [
          Indexing::DerivedFields::MinOrMaxValue.function_def(:min)
        ]

        it "produces a script when `derive_indexed_type_fields` is used with a single min value field" do
          script_id, payload, update_target = script_artifacts_for_widget_currency_from "Widget" do |t|
            t.field "id", "ID"
            t.index "widgets"

            t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
              derive.min_value "oldest_widget_created_at", from: "created_at"
            end
          end

          expect_widget_currency_script(script_id, payload, <<~EOS.chomp)

            boolean oldest_widget_created_at_was_noop = !minValue_idempotentlyUpdateValue(data["created_at"], ctx._source, "oldest_widget_created_at");

            if (!scriptErrors.isEmpty()) {
              throw new IllegalArgumentException("#{DERIVED_INDEX_FAILURE_MESSAGE_PREAMBLE}: " + scriptErrors.join(" "));
            }

            // For records with no new values to index, only skip the update if the document itself doesn't already exist.
            // Otherwise create an (empty) document to reflect the fact that the id has been seen.
            if (ctx._source.id != null && oldest_widget_created_at_was_noop) {
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
            data_params: {"created_at" => dynamic_param_with(source_path: "created_at", cardinality: :many)}
          ))
        end
      end

      context "for both a `min_value` and `max_value` field" do
        include_context "widget currency script support", expected_function_defs: [
          Indexing::DerivedFields::MinOrMaxValue.function_def(:max),
          Indexing::DerivedFields::MinOrMaxValue.function_def(:min)
        ]

        it "produces a script when `derive_indexed_type_fields` is used with both min and max value fields on the same source field" do
          script_id, payload, update_target = script_artifacts_for_widget_currency_from "Widget" do |t|
            t.field "id", "ID"
            t.index "widgets"

            t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
              derive.max_value "newest_widget_created_at", from: "created_at"
              derive.min_value "oldest_widget_created_at", from: "created_at"
            end
          end

          expect_widget_currency_script(script_id, payload, <<~EOS.chomp)

            boolean newest_widget_created_at_was_noop = !maxValue_idempotentlyUpdateValue(data["created_at"], ctx._source, "newest_widget_created_at");
            boolean oldest_widget_created_at_was_noop = !minValue_idempotentlyUpdateValue(data["created_at"], ctx._source, "oldest_widget_created_at");

            if (!scriptErrors.isEmpty()) {
              throw new IllegalArgumentException("#{DERIVED_INDEX_FAILURE_MESSAGE_PREAMBLE}: " + scriptErrors.join(" "));
            }

            // For records with no new values to index, only skip the update if the document itself doesn't already exist.
            // Otherwise create an (empty) document to reflect the fact that the id has been seen.
            if (ctx._source.id != null && newest_widget_created_at_was_noop && oldest_widget_created_at_was_noop) {
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
            data_params: {"created_at" => dynamic_param_with(source_path: "created_at", cardinality: :many)}
          ))
        end

        context "with a nested destination field" do
          it "defaults the parents of the nested field to an empty object, but avoids duplicating that initialization when one parent field has multiple derived subfields" do
            script_id, payload, update_target = script_artifacts_for_widget_currency_from "Widget" do |t|
              t.field "id", "ID"
              t.index "widgets"

              t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
                derive.max_value "widget_created_at.newest", from: "created_at"
                derive.min_value "widget_created_at.oldest", from: "created_at"
              end
            end

            expect_widget_currency_script(script_id, payload, <<~EOS.chomp)
              if (ctx._source.widget_created_at == null) {
                ctx._source.widget_created_at = [:];
              }

              boolean widget_created_at__newest_was_noop = !maxValue_idempotentlyUpdateValue(data["created_at"], ctx._source.widget_created_at, "newest");
              boolean widget_created_at__oldest_was_noop = !minValue_idempotentlyUpdateValue(data["created_at"], ctx._source.widget_created_at, "oldest");

              if (!scriptErrors.isEmpty()) {
                throw new IllegalArgumentException("#{DERIVED_INDEX_FAILURE_MESSAGE_PREAMBLE}: " + scriptErrors.join(" "));
              }

              // For records with no new values to index, only skip the update if the document itself doesn't already exist.
              // Otherwise create an (empty) document to reflect the fact that the id has been seen.
              if (ctx._source.id != null && widget_created_at__newest_was_noop && widget_created_at__oldest_was_noop) {
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
              data_params: {"created_at" => dynamic_param_with(source_path: "created_at", cardinality: :many)}
            ))
          end
        end
      end
    end
  end
end
