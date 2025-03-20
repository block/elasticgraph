# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/date_histogram_grouping"
require "elastic_graph/constants"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe DateHistogramGrouping do
        include AggregationsHelpers

        describe "#key" do
          it "returns the encoded field path" do
            date_histogram_grouping = date_histogram_grouping_of("foo", "bar", "day")

            expect(date_histogram_grouping.key).to eq "foo.bar"
          end

          it "uses GraphQL query field names when they differ from the name of the field in the index" do
            grouping = date_histogram_grouping_of("foo", "bar", "day", field_names_in_graphql_query: ["oof", "rab"])

            expect(grouping.key).to eq "oof.rab"
          end
        end

        describe "#encoded_index_field_path" do
          it "returns the encoded field path" do
            grouping = date_histogram_grouping_of("foo", "bar", "day")

            expect(grouping.encoded_index_field_path).to eq "foo.bar"
          end

          it "uses the names in the index when they differ from the GraphQL names" do
            grouping = date_histogram_grouping_of("oof", "rab", "day", field_names_in_graphql_query: ["foo", "bar"])

            expect(grouping.encoded_index_field_path).to eq "oof.rab"
          end

          it "allows a `name_in_index` that references a child field" do
            grouping = date_histogram_grouping_of("foo.c", "bar.d", "day", field_names_in_graphql_query: ["foo", "bar"])

            expect(grouping.encoded_index_field_path).to eq "foo.c.bar.d"
          end
        end

        describe "#composite_clause" do
          it 'builds a datastore aggregation date histogram grouping clause in the form: {"date_histogram" => {"field" => field_name, "calendar_interval" => interval}}' do
            date_histogram_grouping = date_histogram_grouping_of("foo", "bar", "day")

            expect(date_histogram_grouping.composite_clause).to eq({
              "date_histogram" => {
                "field" => "foo.bar",
                "format" => DATASTORE_DATE_TIME_FORMAT,
                "calendar_interval" => "day",
                "time_zone" => "UTC"
              }
            })
          end

          it "uses the names of the fields in the index rather than the GraphQL query field names when they differ" do
            grouping = date_histogram_grouping_of("foo", "bar", "day", field_names_in_graphql_query: ["oof", "rab"])

            expect(grouping.composite_clause.dig("date_histogram", "field")).to eq("foo.bar")
          end

          %w[year quarter month week day hour minute].each do |calendar_interval|
            it "supports a `calendar_interval` of `#{calendar_interval.inspect}`" do
              date_histogram_grouping = date_histogram_grouping_of("foo", "bar", calendar_interval)

              expect(date_histogram_grouping.composite_clause).to eq({
                "date_histogram" => {
                  "field" => "foo.bar",
                  "format" => DATASTORE_DATE_TIME_FORMAT,
                  "calendar_interval" => calendar_interval.to_s,
                  "time_zone" => "UTC"
                }
              })
            end
          end

          {"second" => "1s", "millisecond" => "1ms"}.each do |interval_name, fixed_interval_value|
            it "supports a `fixed_interval` of `#{fixed_interval_value.inspect}` for #{interval_name.inspect}" do
              date_histogram_grouping = date_histogram_grouping_of("foo", "bar", interval_name)

              expect(date_histogram_grouping.composite_clause).to eq({
                "date_histogram" => {
                  "field" => "foo.bar",
                  "format" => DATASTORE_DATE_TIME_FORMAT,
                  "fixed_interval" => fixed_interval_value,
                  "time_zone" => "UTC"
                }
              })
            end
          end

          it "allows the default time zone of `UTC` to be overridden" do
            date_histogram_grouping = date_histogram_grouping_of("foo", "bar", "day")
            expect(date_histogram_grouping.composite_clause.dig("date_histogram", "time_zone")).to eq("UTC")

            date_histogram_grouping = date_histogram_grouping_of("foo", "bar", "day", time_zone: "America/Los_Angeles")
            expect(date_histogram_grouping.composite_clause.dig("date_histogram", "time_zone")).to eq("America/Los_Angeles")
          end

          it "omits `timezone` if the value is `nil`" do
            date_histogram_grouping = date_histogram_grouping_of("foo", "bar", "day", time_zone: nil)

            expect(date_histogram_grouping.composite_clause.fetch("date_histogram").keys).to contain_exactly("calendar_interval", "field", "format")
          end

          it "includes `offset` if set" do
            date_histogram_grouping = date_histogram_grouping_of("foo", "bar", "day", time_zone: "UTC", offset: "4h")

            expect(date_histogram_grouping.composite_clause).to eq({
              "date_histogram" => {
                "field" => "foo.bar",
                "format" => DATASTORE_DATE_TIME_FORMAT,
                "calendar_interval" => "day",
                "time_zone" => "UTC",
                "offset" => "4h"
              }
            })
          end

          it "merges in the provided grouping options" do
            grouping = date_histogram_grouping_of("foo", "bar", "day")

            clause = grouping.composite_clause(grouping_options: {"optA" => 1, "optB" => false})

            expect(clause["date_histogram"]).to include({"optA" => 1, "optB" => false})
          end

          it "throws a clear exception when given an unsupported interval" do
            date_histogram_grouping = date_histogram_grouping_of("foo", "bar", :fortnight)

            expect {
              date_histogram_grouping.composite_clause
            }.to raise_error ArgumentError, a_string_including("unsupported interval", "fortnight")
          end
        end
      end
    end
  end
end
