# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/script_term_grouping"
require "elastic_graph/constants"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe ScriptTermGrouping do
        include AggregationsHelpers

        let(:script_id) { "some_script_id" }

        describe "#key" do
          it "returns the encoded field path" do
            grouping = script_term_grouping_of("foo", "bar")

            expect(grouping.key).to eq "foo.bar"
          end

          it "uses GraphQL query field names when they differ from the name of the field in the index" do
            grouping = script_term_grouping_of("foo", "bar", field_names_in_graphql_query: ["oof", "rab"])

            expect(grouping.key).to eq "oof.rab"
          end
        end

        describe "#encoded_index_field_path" do
          it "returns the encoded field path" do
            grouping = script_term_grouping_of("foo", "bar")

            expect(grouping.encoded_index_field_path).to eq "foo.bar"
          end

          it "uses the names in the index when they differ from the GraphQL names" do
            grouping = script_term_grouping_of("oof", "rab", field_names_in_graphql_query: ["foo", "bar"])

            expect(grouping.encoded_index_field_path).to eq "oof.rab"
          end

          it "allows a `name_in_index` that references a child field" do
            grouping = script_term_grouping_of("foo.c", "bar.d", field_names_in_graphql_query: ["foo", "bar"])

            expect(grouping.encoded_index_field_path).to eq "foo.c.bar.d"
          end
        end

        describe "#composite_clause" do
          it 'builds a datastore aggregation terms clause in the form: {"terms" => {"script" => {"id" => ... , "params" => ...}}}' do
            grouping = script_term_grouping_of("foo", "bar")

            expect(grouping.composite_clause).to eq({
              "terms" => {
                "script" => {
                  "id" => script_id,
                  "params" => {
                    "field" => "foo.bar"
                  }
                }
              }
            })
          end

          it "uses the names of the fields in the index rather than the GraphQL query field names when they differ" do
            grouping = script_term_grouping_of("foo", "bar", field_names_in_graphql_query: ["oof", "rab"])

            expect(grouping.composite_clause.dig("terms", "script", "params", "field")).to eq("foo.bar")
          end

          it "allows arbitrary params to be set" do
            grouping = script_term_grouping_of("foo", "bar", params: {"some_param" => "some_value", "another_param" => "another_value"})
            expect(grouping.composite_clause.dig("terms", "script", "params", "some_param")).to eq("some_value")
            expect(grouping.composite_clause.dig("terms", "script", "params", "another_param")).to eq("another_value")
          end
        end

        describe "#inner_meta" do
          it "returns inner meta" do
            grouping = script_term_grouping_of("foo", "bar")
            expect(grouping.inner_meta).to eq({
              "key_path" => [
                "key"
              ],
              "merge_into_bucket" => {}
            })
          end
        end

        def script_term_grouping_of(*field_names_in_index, **args)
          super(*field_names_in_index, script_id: script_id, **args)
        end
      end
    end
  end
end
