# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer"
require "elastic_graph/indexer/operation/upsert"
require "json"

module ElasticGraph
  class Indexer
    module Operation
      RSpec.describe Upsert, :factories do
        let(:indexer) { build_indexer }
        let(:component_index_definition) { indexer.datastore_core.index_definitions_by_name.fetch("components") }

        describe "#versioned?" do
          it "always returns `true` since all `Upsert`s use datastore external versioning" do
            event = build_upsert_event(:component, id: "1", __version: 1)
            upsert = new_upsert(event, component_index_definition)

            expect(upsert.versioned?).to be true
          end
        end

        describe "#to_datastore_bulk" do
          it "generates an upsert for a single index" do
            event = build_upsert_event(:component, id: "1", __version: 1)

            expect(new_upsert(event, component_index_definition).to_datastore_bulk).to eq([
              {index: {_index: "components", _id: "1", version: 1, version_type: "external"}},
              event["record"]
            ])
          end

          it "includes a `routing` value based on the configured routing field if the index is using custom routing" do
            indexer = define_indexer do |s|
              s.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.index "my_type" do |i|
                  i.route_with "name"
                end
              end
            end

            event = {
              "op" => "upsert",
              "id" => "1",
              "type" => "MyType",
              "version" => 1,
              "record" => {
                "id" => "1",
                "name" => "Bob"
              }
            }

            index_def = indexer.datastore_core.index_definitions_by_name.fetch("my_type")

            expect(new_upsert(event, index_def, indexer).to_datastore_bulk).to eq([
              {index: {_index: "my_type", _id: "1", version: 1, version_type: "external", routing: "Bob"}},
              event["record"]
            ])
          end

          it "sets the routing value correctly when the routing field has an alternate `name_in_index`" do
            indexer = define_indexer do |s|
              s.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "name", "String", name_in_index: "name_alt"
                t.index "my_type" do |i|
                  i.route_with "name"
                end
              end
            end

            event = {
              "op" => "upsert",
              "id" => "1",
              "type" => "MyType",
              "version" => 1,
              "record" => {
                "id" => "1",
                "name" => "Bob"
              }
            }

            index_def = indexer.datastore_core.index_definitions_by_name.fetch("my_type")

            expect(new_upsert(event, index_def, indexer).to_datastore_bulk).to eq([
              {index: {_index: "my_type", _id: "1", version: 1, version_type: "external", routing: "Bob"}},
              {"id" => "1", "name_alt" => "Bob"}
            ])
          end

          it "uses id for `routing` value if intended value is configured to be ignored by the index" do
            ignored_value = "ignored_value"
            indexer = build_indexer(
              index_definitions: {"my_type" => config_index_def_of(ignore_routing_values: [ignored_value])},
              schema_definition: lambda do |s|
                s.object_type "MyType" do |t|
                  t.field "id", "ID!"
                  t.field "name", "String"
                  t.index "my_type" do |i|
                    i.route_with "name"
                  end
                end
              end
            )

            event = {
              "op" => "upsert",
              "id" => "1",
              "type" => "MyType",
              "version" => 1,
              "record" => {
                "id" => "1",
                "name" => ignored_value
              }
            }

            index_def = indexer.datastore_core.index_definitions_by_name.fetch("my_type")

            expect(new_upsert(event, index_def, indexer).to_datastore_bulk).to eq([
              {index: {_index: "my_type", _id: "1", version: 1, version_type: "external", routing: "1"}},
              event["record"]
            ])
          end

          it "supports nested routing fields" do
            indexer = define_indexer do |s|
              s.object_type "NestedFields" do |t|
                t.field "name", "String"
              end

              s.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "nested_fields", "NestedFields"
                t.index "my_type" do |i|
                  i.route_with "nested_fields.name"
                end
              end
            end

            event = {
              "op" => "upsert",
              "id" => "1",
              "type" => "MyType",
              "version" => 1,
              "record" => {
                "id" => "1",
                "nested_fields" => {"name" => "Bob"}
              }
            }

            index_def = indexer.datastore_core.index_definitions_by_name.fetch("my_type")

            expect(new_upsert(event, index_def, indexer).to_datastore_bulk).to eq([
              {index: {_index: "my_type", _id: "1", version: 1, version_type: "external", routing: "Bob"}},
              event["record"]
            ])
          end

          it "prepares the record to be indexed" do
            indexer = define_indexer do |s|
              s.object_type "WidgetOptions" do |t|
                t.field "size", "Int"
              end

              s.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "options", "WidgetOptions"
                t.index "my_type"
              end
            end

            event = {
              "op" => "upsert",
              "id" => "1",
              "type" => "MyType",
              "version" => 1,
              "record" => {
                "id" => "1",
                "options" => {
                  "size" => 3.0
                }
              }
            }
            index_def = indexer.datastore_core.index_definitions_by_name.fetch("my_type")

            expect(new_upsert(event, index_def, indexer).to_datastore_bulk.last).to match(
              {
                "id" => "1",
                "options" => {
                  # Float-typed integer values are coerced to true ints before indexing
                  "size" => an_instance_of(::Integer).and(eq_to(3))
                }
              }
            )
          end

          it "raises an exception upon missing id" do
            event = {
              "type" => "Component",
              "version" => 1,
              "record" => {"field1" => "value1", "field2" => "value2"}
            }

            expect {
              new_upsert(event, component_index_definition).to_datastore_bulk
            }.to raise_error(KeyError)
          end

          it "raises an exception upon missing record" do
            event = {
              "id" => "1",
              "type" => "Component",
              "version" => 1
            }

            expect {
              new_upsert(event, component_index_definition).to_datastore_bulk
            }.to raise_error(KeyError)
          end
        end

        describe "#categorize" do
          it "categorizes a response as a :success if the status code is 2xx" do
            event = {"id" => "1", "type" => "Component", "version" => 1}
            response = {"index" => {"status" => 200}}
            upsert = new_upsert(event, component_index_definition)

            result = upsert.categorize(response)

            expect(result).to be_an_upsert_result_with(
              category: :success,
              event: event,
              description: nil,
              inspect: "#<ElasticGraph::Indexer::Operation::Result :upsert :success Component:1@v1>"
            )
          end

          it "categorizes a response as :noop if the status code is 409" do
            event = {"id" => "1", "type" => "Component", "version" => 1}
            response = {"index" => {"status" => 409, "error" => {"reason" => "[Z0wCia1lbmd0u80n2ewAzQd8uaB]: version conflict, current version [30001] is higher or equal to the one provided [20001]"}}}
            upsert = new_upsert(event, component_index_definition)

            result = upsert.categorize(response)

            expect(result).to be_an_upsert_result_with(
              category: :noop,
              event: event,
              description: "[Z0wCia1lbmd0u80n2ewAzQd8uaB]: version conflict, current version [30001] is higher or equal to the one provided [20001]"
            )
          end

          it "categorizes a response as :failure if not :noop or :success" do
            event = {"id" => "1", "type" => "Component", "version" => 1}
            response = {"index" => {"status" => 500, "error" => {"reason" => "[Z0wCia1lbmd0u80n2ewAzQd8uaB]: version conflict, current version [30001] is higher or equal to the one provided [20001]"}}}
            upsert = new_upsert(event, component_index_definition)

            result = upsert.categorize(response)

            expect(result).to be_an_upsert_result_with(
              category: :failure,
              event: event,
              description: "[Z0wCia1lbmd0u80n2ewAzQd8uaB]: version conflict, current version [30001] is higher or equal to the one provided [20001]"
            )
          end
        end

        def define_indexer(&block)
          build_indexer(schema_definition: block)
        end

        def new_upsert(event, index_def = component_index_definition, idxr = indexer)
          Upsert.new(event, index_def, idxr.record_preparer_factory.for_latest_json_schema_version)
        end

        def be_an_upsert_result_with(**attributes)
          be_a(Result).and have_attributes(operation_type: :upsert, **attributes)
        end
      end
    end
  end
end
