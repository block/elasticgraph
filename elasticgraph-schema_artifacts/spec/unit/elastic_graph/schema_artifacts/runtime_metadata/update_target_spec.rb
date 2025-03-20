# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/update_target"
require "elastic_graph/spec_support/runtime_metadata_support"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe UpdateTarget do
        include RuntimeMetadataSupport

        it "builds from a minimal hash" do
          update_target = UpdateTarget.from_hash({})

          expect(update_target).to eq UpdateTarget.new(
            type: nil,
            relationship: nil,
            script_id: nil,
            id_source: nil,
            routing_value_source: nil,
            rollover_timestamp_value_source: nil,
            data_params: {},
            metadata_params: {}
          )
        end

        it "allows `data_params` to contain both dynamic params and static params" do
          update_target = normal_indexing_update_target_with(
            data_params: {
              "name" => dynamic_param_with(source_path: "some_name", cardinality: :one),
              "relationshipName" => static_param_with("__self")
            }
          )

          dumped = update_target.to_dumpable_hash
          expect(dumped.fetch("data_params")).to eq({
            "name" => {"cardinality" => "one", "source_path" => "some_name"},
            "relationshipName" => {"value" => "__self"}
          })

          reloaded = UpdateTarget.from_hash(dumped)
          expect(reloaded).to eq(update_target)
        end

        describe "#for_normal_indexing?" do
          it "returns `false` for a derived indexing update target" do
            update_target = derived_indexing_update_target_with(type: "Type1")

            expect(update_target.for_normal_indexing?).to eq(false)
          end

          it "returns `true` for a normal indexing update target" do
            update_target = normal_indexing_update_target_with(type: "Type1")

            expect(update_target.for_normal_indexing?).to eq(true)
          end
        end

        describe "#params_for" do
          it "includes the given `doc_id` as `id`" do
            params = params_for(doc_id: "abc123")

            expect(params).to include("id" => "abc123")
          end

          it "extracts `metadata_params` from `event` and includes them" do
            params = params_for(
              metadata_params: {
                "foo" => static_param_with(43),
                "bar" => dynamic_param_with(source_path: "some.nested.field", cardinality: :one),
                "bazz" => dynamic_param_with(source_path: "some.other.field", cardinality: :many)
              },
              event: {
                "some" => {
                  "nested" => {"field" => "hello"},
                  "other" => {"field" => 12}
                }
              }
            )

            without_id_or_data = params.except("id", "data")

            expect(without_id_or_data).to eq(
              "foo" => 43,
              "bar" => "hello",
              "bazz" => [12]
            )
          end

          it "extracts `event_params` from `prepared_record` and include them under `data`" do
            params = params_for(
              data_params: {
                "foo" => static_param_with(43),
                "bar" => dynamic_param_with(source_path: "some.nested.field", cardinality: :one),
                "bazz" => dynamic_param_with(source_path: "some.other.field", cardinality: :many)
              },
              prepared_record: {
                "some" => {
                  "nested" => {"field" => "hello"},
                  "other" => {"field" => 12}
                }
              }
            )

            expect(params.fetch("data")).to eq(
              "foo" => 43,
              "bar" => "hello",
              "bazz" => [12]
            )
          end

          def params_for(doc_id: "doc_id", event: {}, prepared_record: {}, data_params: {}, metadata_params: {})
            update_target = normal_indexing_update_target_with(
              data_params: data_params,
              metadata_params: metadata_params
            )

            update_target.params_for(doc_id: doc_id, event: event, prepared_record: prepared_record)
          end
        end
      end
    end
  end
end
