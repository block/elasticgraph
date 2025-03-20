# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/index_definition/index"
require_relative "implementation_shared_examples"

module ElasticGraph
  class DatastoreCore
    module IndexDefinition
      RSpec.describe Index do
        include_examples "an IndexDefinition implementation (unit specs)" do
          def define_datastore_core_with_index(index_name, config_overrides: {}, schema_def: nil, **index_options, &block)
            build_datastore_core(schema_definition: lambda do |s|
              s.object_type "NestedFields" do |t|
                t.field "nested_id", "ID"
              end

              s.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "created_at", "DateTime!"
                t.field "nested_fields", "NestedFields"
                t.index(index_name, **index_options, &block)
              end

              schema_def&.call(s)
            end, **config_overrides)
          end

          it "inspects well" do
            index = define_index("colors")

            expect(index.inspect).to eq "#<ElasticGraph::DatastoreCore::IndexDefinition::Index colors>"
          end

          describe "#index_name_for_writes" do
            it "returns the configured index name" do
              index = define_index("things")
              test_record = {"id" => "1", "created_at" => "2020-04-23T18:25:43.511Z"}

              expect(index.index_name_for_writes(test_record)).to eq("things")
            end

            it "ignores the `timestamp_field_path` argument if passed" do
              index = define_index("things")
              test_record = {"id" => "1", "created_at" => "2020-04-23T18:25:43.511Z"}

              expect(index.index_name_for_writes(test_record, timestamp_field_path: nil)).to eq("things")
              expect(index.index_name_for_writes(test_record, timestamp_field_path: "created_at")).to eq("things")
            end
          end
        end
      end
    end
  end
end
