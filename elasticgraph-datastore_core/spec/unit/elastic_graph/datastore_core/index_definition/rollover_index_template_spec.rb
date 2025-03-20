# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/index_definition/rollover_index_template"
require "elastic_graph/errors"
require_relative "implementation_shared_examples"

module ElasticGraph
  class DatastoreCore
    module IndexDefinition
      RSpec.describe RolloverIndexTemplate do
        include_examples "an IndexDefinition implementation (unit specs)" do
          def define_datastore_core_with_index(index_name, schema_def: nil, config_overrides: {}, timestamp_path: "created_at", **index_options, &block)
            build_datastore_core(schema_definition: lambda do |s|
              s.object_type "NestedFields" do |t|
                t.field "created_at", "DateTime"
                t.field "created_on", "Date"
                t.field "nested_id", "ID"
              end

              s.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "created_at", "DateTime!"
                t.field "created_on", "Date"
                t.field "nested_fields", "NestedFields"
                t.index(index_name, **index_options) do |i|
                  i.rollover :monthly, "created_at" # timestamp_path
                  block&.call(i)
                end
              end

              schema_def&.call(s)
            end, **config_overrides)
          end

          it "inspects well" do
            index = define_index("colors")

            expect(index.inspect).to eq "#<ElasticGraph::DatastoreCore::IndexDefinition::RolloverIndexTemplate colors>"
          end

          describe "#index_name_for_writes" do
            shared_examples_for "index_name_for_writes" do |timestamp_field, timestamp_value|
              let(:test_record) { {"id" => "1", timestamp_field => timestamp_value, "nested_fields" => {timestamp_field => timestamp_value}} }

              {
                daily: "things_rollover__2020-04-23",
                monthly: "things_rollover__2020-04",
                yearly: "things_rollover__2020"
              }.each do |frequency, expected_index_name|
                it "returns the correct rollover index to write to when the frequency is `#{frequency.inspect}`" do
                  index = define_index("things") do |i|
                    i.rollover frequency, timestamp_field
                  end

                  expect(index.index_name_for_writes(test_record)).to eq(expected_index_name)
                end
              end

              it "supports nested rollover timestamp fields" do
                index = define_index "things" do |i|
                  i.rollover :monthly, "nested_fields.#{timestamp_field}"
                end

                expect(index.index_name_for_writes(test_record)).to eq("things_rollover__2020-04")
              end

              it "allows an alternate `timestamp_field_path` to be passed as an argument to support updates against a different type from the source event type" do
                index1 = define_index "things" do |i|
                  i.rollover :monthly, "nested_fields.#{timestamp_field}"
                end

                record_without_nested_fields = test_record.except("nested_fields")
                expect(index1.index_name_for_writes(record_without_nested_fields, timestamp_field_path: timestamp_field)).to eq("things_rollover__2020-04")

                index2 = define_index "things" do |i|
                  i.rollover :monthly, timestamp_field
                end

                record_without_timestamp_field = test_record.except(timestamp_field)
                expect(index2.index_name_for_writes(record_without_timestamp_field, timestamp_field_path: "nested_fields.#{timestamp_field}")).to eq("things_rollover__2020-04")
              end

              it "returns the name of a custom timestamp range index if the record's timestamp falls in a custom range" do
                index = define_index("my_type", config_overrides: {
                  index_definitions: {
                    "my_type" => config_index_def_of(custom_timestamp_ranges: [
                      {
                        "index_name_suffix" => "before_2015",
                        "lt" => "2015-01-01T00:00:00Z",
                        "setting_overrides" => {}
                      },
                      {
                        "index_name_suffix" => "2016_and_2017",
                        "gte" => "2016-01-01T00:00:00Z",
                        "lt" => "2018-01-01T00:00:00Z",
                        "setting_overrides" => {}
                      }
                    ])
                  }
                }) do |i|
                  i.rollover :monthly, timestamp_field
                end

                expect(index.index_name_for_writes({timestamp_field => normalize_timestamp_value("2014-01-01T00:00:00Z")})).to eq "my_type_rollover__before_2015"
                expect(index.index_name_for_writes({timestamp_field => normalize_timestamp_value("2015-01-01T00:00:00Z")})).to eq "my_type_rollover__2015-01"
                expect(index.index_name_for_writes({timestamp_field => normalize_timestamp_value("2016-01-01T00:00:00Z")})).to eq "my_type_rollover__2016_and_2017"
                expect(index.index_name_for_writes({timestamp_field => normalize_timestamp_value("2017-01-01T00:00:00Z")})).to eq "my_type_rollover__2016_and_2017"
                expect(index.index_name_for_writes({timestamp_field => normalize_timestamp_value("2018-01-01T00:00:00Z")})).to eq "my_type_rollover__2018-01"
              end

              it "raises exception if rollover index configuration references missing field" do
                index = define_index("things") do |i|
                  i.rollover :monthly, timestamp_field
                end

                expect {
                  index.index_name_for_writes(test_record.except(timestamp_field))
                }.to raise_error(KeyError, a_string_including(timestamp_field))
              end
            end

            context "when the rollover timestamp field is a `DateTime`" do
              include_examples "index_name_for_writes", "created_at", "2020-04-23T18:25:43.511Z" do
                def normalize_timestamp_value(value)
                  value
                end

                it "returns the correct rollover index to write to when the frequency is :hourly" do
                  index = define_index("things") do |i|
                    i.rollover :hourly, "created_at"
                  end

                  expect(index.index_name_for_writes(test_record)).to eq("things_rollover__2020-04-23-18")
                end
              end

              it "returns the correct rollover index from `related_rollover_index_for_timestamp`" do
                index = define_index("things") do |i|
                  i.rollover :hourly, "created_at"
                end

                rollover_index = index.related_rollover_index_for_timestamp("2018-01-01T08:07:03Z")

                expect(rollover_index).to be_a RolloverIndex
                expect(rollover_index.name).to eq("things_rollover__2018-01-01-08")
              end
            end

            context "when the rollover timestamp field is a `Date`" do
              include_examples "index_name_for_writes", "created_on", "2020-04-23" do
                def normalize_timestamp_value(value)
                  value.split("T").first # pull out just the date part
                end

                it "returns an index name based on the midnight hour if the frequency is :hourly" do
                  index = define_index("things") do |i|
                    i.rollover :hourly, "created_on"
                  end

                  # `:hourly` doesn't really make sense to use with a `Date` field, but that's a schema definition
                  # mistake, and here it's reasonable to just use midnight as the hour for every date value.
                  expect(index.index_name_for_writes(test_record)).to eq("things_rollover__2020-04-23-00")
                end

                it "returns the correct rollover index from `related_rollover_index_for_timestamp`" do
                  index = define_index("things") do |i|
                    i.rollover :daily, "created_on"
                  end

                  rollover_index = index.related_rollover_index_for_timestamp("2018-01-01")

                  expect(rollover_index).to be_a RolloverIndex
                  expect(rollover_index.name).to eq("things_rollover__2018-01-01")
                end
              end
            end
          end
        end

        it "raises an exception when rollover frequency is unsupported" do
          expect {
            define_index do |i|
              i.rollover :secondly, "created_at"
            end
          }.to raise_error(Errors::SchemaError, a_string_including("Rollover index config 'timestamp_field' or 'frequency' is invalid"))
        end

        describe "its constants" do
          specify "`ROLLOVER_SUFFIX_FORMATS_BY_FREQUENCY` and `TIME_UNIT_BY_FREQUENCY` have the same keys" do
            expect(RolloverIndexTemplate::ROLLOVER_SUFFIX_FORMATS_BY_FREQUENCY.keys).to match_array(RolloverIndexTemplate::TIME_UNIT_BY_FREQUENCY.keys)
          end

          specify "all `TIME_UNIT_BY_FREQUENCY` values are valid arguments to `Support::TimeUtil.advance_one_unit`" do
            now = ::Time.now

            RolloverIndexTemplate::TIME_UNIT_BY_FREQUENCY.values.each do |unit|
              expect(Support::TimeUtil.advance_one_unit(now, unit)).to be_a ::Time
            end
          end
        end
      end
    end
  end
end
