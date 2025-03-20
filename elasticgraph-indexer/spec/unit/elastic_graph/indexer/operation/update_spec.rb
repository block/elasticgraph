# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer"
require "elastic_graph/indexer/operation/update"
require "elastic_graph/spec_support/runtime_metadata_support"
require "json"

module ElasticGraph
  class Indexer
    module Operation
      RSpec.describe Update do
        include SchemaArtifacts::RuntimeMetadata::RuntimeMetadataSupport

        let(:indexer) { build_indexer }
        let(:event) do
          {
            "op" => "upsert",
            "id" => "3",
            "type" => "Widget",
            "version" => 1,
            "record" => {
              "workspace_id" => "17",
              "workspace_ids" => ["17", "18", "19", "17", "17"],
              "name" => "thing1",
              "created_at" => "2021-06-10T12:30:00Z",
              "size" => 3,
              "embedded_values" => {
                "workspace_id" => "embedded_workspace_id",
                "name" => "embedded_name"
              }
            }
          }
        end

        describe "#versioned?" do
          it "returns `false` for a derived indexing update since we don't keep track of source versions on the derived document" do
            update = update_with_update_target(derived_indexing_update_target_with(type: "WidgetCurrency"))

            expect(update.versioned?).to be false
          end

          it "returns `true` for a normal indexing update since we keep track of versions in `__versions`" do
            update = update_with_update_target(normal_indexing_update_target_with(type: "Widget"))

            expect(update.versioned?).to be true
          end
        end

        it "has a readable `#inspect` and `#to_s`" do
          update = update_with_update_target(derived_indexing_update_target_with(type: "WidgetWorkspace"))

          expect(update.inspect).to eq("#<ElasticGraph::Indexer::Operation::Update event=Widget:3@v1 target=WidgetWorkspace>")
          expect(update.to_s).to eq(update.inspect)
        end

        describe "#to_datastore_bulk" do
          it "returns the bulk form of an update request based on the derived index configuration" do
            indexer = indexer_with_widget_workspace_index_definition do |index|
              # no customization
            end

            operations = operations_for_indexer(indexer)

            expect(operations.size).to eq(1)
            expect(operations.flat_map(&:to_datastore_bulk)).to eq [
              {update: {_id: "17", _index: "widget_workspaces", retry_on_conflict: Update::CONFLICT_RETRIES}},
              {
                script: {id: operations.first.update_target.script_id, params: {
                  "data" => {"name" => ["thing1"]},
                  "id" => "17"
                }},
                scripted_upsert: true,
                upsert: {}
              }
            ]
          end

          it "includes any metadata params defined on the update target" do
            indexer = indexer_with_widget_workspace_index_definition do |index|
              # no customization
            end

            operations = operations_for_indexer(indexer)
            expect(operations.size).to eq(1)
            operation = operations.first.with(update_target: normal_indexing_update_target_with(
              type: "Widget",
              data_params: {"name" => dynamic_param_with(source_path: "name", cardinality: :one)},
              metadata_params: {
                "staticValue" => static_param_with(47),
                "sourceType" => dynamic_param_with(source_path: "type", cardinality: :one)
              }
            ))

            expect(operation.to_datastore_bulk).to eq [
              {update: {_id: "17", _index: "widget_workspaces", retry_on_conflict: Update::CONFLICT_RETRIES}},
              {
                script: {id: INDEX_DATA_UPDATE_SCRIPT_ID, params: {
                  "data" => {"name" => "thing1"},
                  "id" => "17",
                  "staticValue" => 47,
                  "sourceType" => "Widget",
                  LIST_COUNTS_FIELD => {"sizes" => 0, "widget_names" => 0}
                }},
                scripted_upsert: true,
                upsert: {}
              }
            ]
          end

          it "returns no datastore bulk actions if the source document lacks the id field of the update target" do
            indexer = indexer_with_widget_workspace_index_definition do |index|
              # no customization
            end

            operations = operations_for_indexer(indexer, event: event.merge("record" => event.fetch("record").merge("workspace_id" => nil)))

            expect(operations).to eq []
          end

          it "returns no datastore bulk actions if the source document has an empty string for the id field of the update target" do
            indexer = indexer_with_widget_workspace_index_definition do |index|
              # no customization
            end

            operations = operations_for_indexer(indexer, event: event.merge("record" => event.fetch("record").merge("workspace_id" => "")))

            expect(operations).to eq []
          end

          it "returns no datastore bulk actions if the source document has only whitespace for the id field of the update target" do
            indexer = indexer_with_widget_workspace_index_definition do |index|
              # no customization
            end

            operations = operations_for_indexer(indexer, event: event.merge("record" => event.fetch("record").merge("workspace_id" => "  ")))

            expect(operations).to eq []
          end

          it "still returns an update even if all params are empty so the script can still create a record of a derived indexing type (in case we are seeing it for the first time)" do
            indexer = indexer_with_widget_workspace_index_definition do |index|
              # no customization
            end

            operations = operations_for_indexer(indexer, event: event.merge("record" => event.fetch("record").merge("name" => nil)))

            expect(operations.size).to eq(1)
            expect(operations.flat_map(&:to_datastore_bulk)).to eq [
              {update: {_id: "17", _index: "widget_workspaces", retry_on_conflict: Update::CONFLICT_RETRIES}},
              {
                script: {id: operations.first.update_target.script_id, params: {
                  "data" => {"name" => []},
                  "id" => "17"
                }},
                scripted_upsert: true,
                upsert: {}
              }
            ]
          end

          it "supports a nested id_source field" do
            indexer = indexer_with_widget_workspace_index_definition(id_source: "embedded_values.workspace_id") do |index|
              # no customization
            end

            operations = operations_for_indexer(indexer)

            expect(operations.size).to eq(1)
            expect(operations.flat_map(&:to_datastore_bulk)).to eq [
              {update: {_id: "embedded_workspace_id", _index: "widget_workspaces", retry_on_conflict: Update::CONFLICT_RETRIES}},
              {
                script: {id: operations.first.update_target.script_id, params: {
                  "data" => {"name" => ["thing1"]},
                  "id" => "embedded_workspace_id"
                }},
                scripted_upsert: true,
                upsert: {}
              }
            ]
          end

          it "tolerates the record lacking anything at the `source_path` (e.g. for an event published before the field was added to the schema)" do
            indexer = indexer_with_widget_workspace_index_definition(set_field_source: "embedded_values.missing_field") do |index|
              # no customization
            end

            operations = operations_for_indexer(indexer)

            expect(operations.size).to eq(1)
            operation = operations.first.with(update_target: operations.first.update_target.with(data_params: {
              "embedded_values.missing_field" => dynamic_param_with(source_path: "embedded_values.missing_field", cardinality: :many),
              "name" => dynamic_param_with(source_path: "some_field_that_is_not_in_record", cardinality: :one)
            }))
            expect(operation.to_datastore_bulk).to eq [
              {update: {_id: "17", _index: "widget_workspaces", retry_on_conflict: Update::CONFLICT_RETRIES}},
              {
                script: {id: operations.first.update_target.script_id, params: {
                  "data" => {"embedded_values.missing_field" => [], "name" => nil},
                  "id" => "17"
                }},
                scripted_upsert: true,
                upsert: {}
              }
            ]
          end

          it "gets the param value from the `source_path` rather than the param name if they differ" do
            indexer = indexer_with_widget_workspace_index_definition do |index|
              # no customization
            end

            operations = operations_for_indexer(indexer)
            expect(operations.size).to eq(1)

            operation = operations.first.with(update_target: operations.first.update_target.with(data_params: {
              # Here we've swapped the source_paths with the param names.
              "embedded_values" => dynamic_param_with(source_path: "name", cardinality: :many),
              "name" => dynamic_param_with(source_path: "embedded_values", cardinality: :one)
            }))

            expect(operation.to_datastore_bulk).to eq [
              {update: {_id: "17", _index: "widget_workspaces", retry_on_conflict: Update::CONFLICT_RETRIES}},
              {
                script: {id: operations.first.update_target.script_id, params: {
                  "data" => {
                    "embedded_values" => ["thing1"],
                    "name" => {
                      "name" => "embedded_name",
                      "workspace_id" => "embedded_workspace_id"
                    }
                  },
                  "id" => "17"
                }},
                scripted_upsert: true,
                upsert: {}
              }
            ]
          end

          it "prepares the record to be indexed before extracting params so that we pass values to the script in the same form we index them" do
            indexer = indexer_with_widget_workspace_index_definition(set_field: "sizes", set_field_source: "size") do |index|
              # no customization
            end

            operations = operations_for_indexer(indexer, event: event.merge(
              "record" => event.fetch("record").merge(
                "size" => 4.0
              )
            ))

            expect(operations.size).to eq(1)
            expect(operations.flat_map(&:to_datastore_bulk)).to match [
              {update: {_id: "17", _index: "widget_workspaces", retry_on_conflict: Update::CONFLICT_RETRIES}},
              {
                script: {id: operations.first.update_target.script_id, params: {
                  # Float-typed integer values are coerced to true ints before indexing
                  "data" => {"size" => [an_instance_of(::Integer).and(eq_to(4))]},
                  "id" => "17"
                }},
                scripted_upsert: true,
                upsert: {}
              }
            ]
          end

          it "returns an update operation for each of the unique id values when there is a list of ids available" do
            indexer = indexer_with_widget_workspace_index_definition(id_source: "workspace_ids") do |index|
              # no customization
            end

            operations = operations_for_indexer(indexer)

            expect(operations.size).to eq(3)
            expect(operations.flat_map(&:to_datastore_bulk)).to eq [
              {update: {_id: "17", _index: "widget_workspaces", retry_on_conflict: Update::CONFLICT_RETRIES}},
              {
                script: {id: operations.first.update_target.script_id, params: {
                  "data" => {"name" => ["thing1"]},
                  "id" => "17"
                }},
                scripted_upsert: true,
                upsert: {}
              },
              {update: {_id: "18", _index: "widget_workspaces", retry_on_conflict: Update::CONFLICT_RETRIES}},
              {
                script: {id: operations.first.update_target.script_id, params: {
                  "data" => {"name" => ["thing1"]},
                  "id" => "18"
                }},
                scripted_upsert: true,
                upsert: {}
              },
              {update: {_id: "19", _index: "widget_workspaces", retry_on_conflict: Update::CONFLICT_RETRIES}},
              {
                script: {id: operations.first.update_target.script_id, params: {
                  "data" => {"name" => ["thing1"]},
                  "id" => "19"
                }},
                scripted_upsert: true,
                upsert: {}
              }
            ]
          end

          context "when the derived index is a rollover index" do
            let(:event) do
              base = super()
              base.merge("record" => base.fetch("record").merge(
                "workspace_created_at" => "1995-04-23T00:23:45Z"
              ))
            end

            it "targets the index identified by the rollover timestamp field" do
              indexer = indexer_with_widget_workspace_index_definition derived_index_rollover_with: "workspace_created_at" do |index|
                index.rollover :yearly, "was_created_at"
              end

              operations = operations_for_indexer(indexer)

              expect(operations.flat_map(&:to_datastore_bulk).first).to eq({update: {
                _id: "17",
                _index: "widget_workspaces_rollover__1995",
                retry_on_conflict: Update::CONFLICT_RETRIES
              }})
            end
          end

          context "when the derived index uses custom routing" do
            let(:event) do
              base = super()
              base.merge("record" => base.fetch("record").merge(
                "num" => 3.0 # an integer-valued-float that the record preparer normalizes
              ))
            end

            it "includes the `routing` value in the update calls" do
              indexer = indexer_with_widget_workspace_index_definition derived_index_route_with: "embedded_values.name" do |index|
                index.route_with "other_id"
              end

              operations = operations_for_indexer(indexer)

              expect(operations.flat_map(&:to_datastore_bulk).first).to eq({update: {
                _id: "17",
                _index: "widget_workspaces",
                routing: "embedded_name",
                retry_on_conflict: Update::CONFLICT_RETRIES
              }})
            end

            it "uses the prepared record to get the routing value so that the data is formatted for the datastore" do
              indexer = indexer_with_widget_workspace_index_definition derived_index_route_with: "num" do |index|
                index.route_with "num"
              end

              operations = operations_for_indexer(indexer)

              expect(operations.flat_map(&:to_datastore_bulk).first).to eq({update: {
                _id: "17",
                _index: "widget_workspaces",
                routing: "3",
                retry_on_conflict: Update::CONFLICT_RETRIES
              }})
            end

            it "correctly falls back to the id from `id_source` when the routing value is an ignored routing value" do
              indexer = indexer_with_widget_workspace_index_definition(
                derived_index_route_with: "embedded_values.name",
                config_overrides: {
                  index_definitions: {
                    "widgets" => config_index_def_of,
                    "widget_workspaces" => config_index_def_of(ignore_routing_values: ["embedded_name"])
                  }
                }
              ) do |index|
                index.route_with "other_id"
              end

              operations = operations_for_indexer(indexer)

              expect(operations.flat_map(&:to_datastore_bulk).first).to eq({update: {
                _id: "17",
                _index: "widget_workspaces",
                routing: "17",
                retry_on_conflict: Update::CONFLICT_RETRIES
              }})
            end
          end

          def operations_for_indexer(indexer, event: self.event)
            update_target = indexer.schema_artifacts.runtime_metadata.object_types_by_name.fetch("Widget").update_targets.first
            index_defs_by_name = indexer.datastore_core.index_definitions_by_name

            Update.operations_for(
              event: event,
              destination_index_def: index_defs_by_name.fetch("widget_workspaces"),
              record_preparer: indexer.record_preparer_factory.for_latest_json_schema_version,
              update_target: update_target,
              destination_index_mapping: indexer.schema_artifacts.index_mappings_by_index_def_name.fetch("widget_workspaces")
            )
          end

          def indexer_with_widget_workspace_index_definition(
            id_source: "workspace_id",
            set_field: "widget_names",
            set_field_source: "name",
            derived_index_route_with: nil,
            derived_index_rollover_with: nil,
            config_overrides: {},
            &block
          )
            indexer_with_schema(**config_overrides) do |schema|
              schema.object_type "WidgetWorkspace" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "other_id", "ID"
                t.field "num", "Int"
                t.field "widget_names", "[String!]!"
                t.field "was_created_at", "DateTime" # intentionally different from `created_at` since that's used on `Widget`
                t.field "sizes", "[Int!]!"
                t.index "widget_workspaces", &block
              end

              schema.object_type "WidgetEmbeddedValues" do |t|
                t.field "workspace_id", "ID"
                t.field "name", "String"
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "workspace_id", "ID"
                t.field "workspace_ids", "[ID!]!"
                t.field "name", "String"
                t.field "num", "Int"
                t.field "size", "Int"
                t.field "created_at", "DateTime"
                t.field "workspace_created_at", "DateTime"
                t.field "embedded_values", "WidgetEmbeddedValues"
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_at"
                  i.route_with "workspace_id"
                end

                t.derive_indexed_type_fields(
                  "WidgetWorkspace",
                  from_id: id_source,
                  route_with: derived_index_route_with,
                  rollover_with: derived_index_rollover_with
                ) do |derive|
                  derive.append_only_set set_field, from: set_field_source
                end
              end
            end
          end

          def indexer_with_schema(**overrides, &block)
            build_indexer(schema_definition: block, **overrides)
          end
        end

        describe "#categorize" do
          let(:operation) do
            update_with_update_target(derived_indexing_update_target_with(script_id: "some_update_script"), doc_id: "some_doc_id")
          end

          it "categorizes a response as :success if the status code is 2xx and result is not noop" do
            response = {"update" => {"status" => 200}}

            result = operation.categorize(response)

            expect(result).to be_an_update_result_with(category: :success, event: event, description: nil)
          end

          it "categorizes a response as :noop if result is noop" do
            response = {"update" => {"status" => 200, "result" => "noop"}}

            result = operation.categorize(response)

            expect(result).to be_an_update_result_with(category: :noop, event: event, description: nil)
          end

          it "categorizes a response as :noop if the script threw an exception with our noop preamble in the message" do
            response = {"update" => {"status" => 500, "error" => {
              "reason" => "an exception was thrown",
              "caused_by" => {"caused_by" => {
                "reason" => "#{UPDATE_WAS_NOOP_MESSAGE_PREAMBLE}the version was too low"
              }}
            }}}

            result = operation.categorize(response)

            expect(result).to be_an_update_result_with(category: :noop, event: event, description: "the version was too low")
          end

          it "categorizes a response as :failure if not :noop or :success" do
            response = {"update" => {"status" => 500, "error" => {"reason" => "an exception was thrown"}}}

            result = operation.categorize(response)

            expect(result).to be_an_update_result_with(
              category: :failure,
              event: event,
              description: <<~EOS.strip
                some_update_script(applied to `some_doc_id`): an exception was thrown; full response: {
                  "update": {
                    "status": 500,
                    "error": {
                      "reason": "an exception was thrown"
                    }
                  }
                }
              EOS
            )
          end
        end

        def be_an_update_result_with(**attributes)
          be_a(Result).and have_attributes(operation_type: :update, **attributes)
        end

        def update_with_update_target(update_target, doc_id: event.fetch("id"))
          Update.new(
            event: event,
            prepared_record: nil,
            destination_index_def: nil,
            update_target: update_target,
            doc_id: doc_id,
            destination_index_mapping: {}
          )
        end
      end
    end
  end
end
