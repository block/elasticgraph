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
    RSpec.describe "Update scripts for `immutable_value` fields" do
      include SchemaArtifacts::RuntimeMetadata::RuntimeMetadataSupport

      include_context "widget currency script support", expected_function_defs: [
        Indexing::DerivedFields::ImmutableValue::IDEMPOTENTLY_SET_VALUE
      ]

      it "produces a script when `derive_indexed_type_fields` is used with a single `immutable_value` field" do
        script_id, payload, update_target = script_artifacts_for_widget_currency_from "Widget" do |t|
          t.field "id", "ID"
          t.index "widgets"

          t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
            derive.immutable_value "name", from: "cost_currency_name", nullable: true, can_change_from_null: false
          end
        end

        expect_widget_currency_script(script_id, payload, expected_code_for_name_field(
          nullable: true,
          can_change_from_null: false
        ))

        expect(update_target).to eq(derived_indexing_update_target_with(
          type: "WidgetCurrency",
          script_id: script_id,
          id_source: "cost.currency",
          routing_value_source: nil,
          rollover_timestamp_value_source: nil,
          data_params: {"cost_currency_name" => dynamic_param_with(source_path: "cost_currency_name", cardinality: :many)}
        ))
      end

      it "defaults `nullable` to `true` and `can_change_from_null` to `false`" do
        script_id, payload, _ = script_artifacts_for_widget_currency_from "Widget" do |t|
          t.field "id", "ID"
          t.index "widgets"

          t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
            derive.immutable_value "name", from: "cost_currency_name"
          end
        end

        expect_widget_currency_script(script_id, payload, expected_code_for_name_field(
          nullable: true,
          can_change_from_null: false
        ))
      end

      it "allows `nullable` to be set to `false`" do
        script_id, payload, _ = script_artifacts_for_widget_currency_from "Widget" do |t|
          t.field "id", "ID"
          t.index "widgets"

          t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
            derive.immutable_value "name", from: "cost_currency_name", nullable: false, can_change_from_null: false
          end
        end

        expect_widget_currency_script(script_id, payload, expected_code_for_name_field(
          nullable: false,
          can_change_from_null: false
        ))
      end

      it "allows `can_change_from_null` to be set to `true`" do
        script_id, payload, _ = script_artifacts_for_widget_currency_from "Widget" do |t|
          t.field "id", "ID"
          t.index "widgets"

          t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
            derive.immutable_value "name", from: "cost_currency_name", nullable: true, can_change_from_null: true
          end
        end

        expect_widget_currency_script(script_id, payload, expected_code_for_name_field(
          nullable: true,
          can_change_from_null: true
        ))
      end

      it "does not allow `can_change_from_null` to be `true` when `nullable` is `false`" do
        expect {
          script_artifacts_for_widget_currency_from "Widget" do |t|
            t.field "id", "ID"
            t.index "widgets"

            t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
              derive.immutable_value "name", from: "cost_currency_name", nullable: false, can_change_from_null: true
            end
          end
        }.to raise_error Errors::SchemaError, a_string_including("nullable: false", "can_change_from_null: true")
      end

      context "with a nested destination field" do
        it "defaults the parents of the nested field to an empty object, but avoids duplicating that initialization when one parent field has multiple derived subfields" do
          script_id, payload, update_target = script_artifacts_for_widget_currency_from "Widget" do |t|
            t.field "id", "ID"
            t.index "widgets"

            t.derive_indexed_type_fields "WidgetCurrency", from_id: "cost.currency" do |derive|
              derive.immutable_value "details.unit", from: "cost_currency_unit", nullable: true, can_change_from_null: false
              derive.immutable_value "details.symbol", from: "cost_currency_symbol", nullable: true, can_change_from_null: false
            end
          end

          expect_widget_currency_script(script_id, payload, <<~EOS.strip)
            if (ctx._source.details == null) {
              ctx._source.details = [:];
            }

            boolean details__symbol_was_noop = !immutableValue_idempotentlyUpdateValue(scriptErrors, data["cost_currency_symbol"], ctx._source.details, "details.symbol", "symbol", true, false);
            boolean details__unit_was_noop = !immutableValue_idempotentlyUpdateValue(scriptErrors, data["cost_currency_unit"], ctx._source.details, "details.unit", "unit", true, false);

            if (!scriptErrors.isEmpty()) {
              throw new IllegalArgumentException("#{DERIVED_INDEX_FAILURE_MESSAGE_PREAMBLE}: " + scriptErrors.join(" "));
            }

            // For records with no new values to index, only skip the update if the document itself doesn't already exist.
            // Otherwise create an (empty) document to reflect the fact that the id has been seen.
            if (ctx._source.id != null && details__symbol_was_noop && details__unit_was_noop) {
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
              "cost_currency_unit" => dynamic_param_with(source_path: "cost_currency_unit", cardinality: :many),
              "cost_currency_symbol" => dynamic_param_with(source_path: "cost_currency_symbol", cardinality: :many)
            }
          ))
        end
      end

      def expected_code_for_name_field(nullable:, can_change_from_null:)
        <<~EOS.chomp

          boolean name_was_noop = !immutableValue_idempotentlyUpdateValue(scriptErrors, data["cost_currency_name"], ctx._source, "name", "name", #{nullable}, #{can_change_from_null});

          if (!scriptErrors.isEmpty()) {
            throw new IllegalArgumentException("#{DERIVED_INDEX_FAILURE_MESSAGE_PREAMBLE}: " + scriptErrors.join(" "));
          }

          // For records with no new values to index, only skip the update if the document itself doesn't already exist.
          // Otherwise create an (empty) document to reflect the fact that the id has been seen.
          if (ctx._source.id != null && name_was_noop) {
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
      end
    end
  end
end
