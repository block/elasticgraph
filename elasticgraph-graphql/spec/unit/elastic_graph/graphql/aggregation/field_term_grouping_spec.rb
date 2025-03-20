# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/field_term_grouping"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe FieldTermGrouping do
        include AggregationsHelpers

        describe "#key" do
          it "returns the encoded field path" do
            term_grouping = field_term_grouping_of("foo", "bar")

            expect(term_grouping.key).to eq "foo.bar"
          end

          it "uses GraphQL query field names when they differ from the name of the field in the index" do
            grouping = field_term_grouping_of("foo", "bar", field_names_in_graphql_query: ["oof", "rab"])

            expect(grouping.key).to eq "oof.rab"
          end
        end

        describe "#encoded_index_field_path" do
          it "returns the encoded field path" do
            grouping = field_term_grouping_of("foo", "bar")

            expect(grouping.encoded_index_field_path).to eq "foo.bar"
          end

          it "uses the names in the index when they differ from the GraphQL names" do
            grouping = field_term_grouping_of("oof", "rab", field_names_in_graphql_query: ["foo", "bar"])

            expect(grouping.encoded_index_field_path).to eq "oof.rab"
          end

          it "allows a `name_in_index` that references a child field" do
            grouping = field_term_grouping_of("foo.c", "bar.d", field_names_in_graphql_query: ["foo", "bar"])

            expect(grouping.encoded_index_field_path).to eq "foo.c.bar.d"
          end
        end

        describe "#composite_clause" do
          it 'builds a datastore aggregation term grouping clause in the form: {"terms" => {"field" => field_name}}' do
            term_grouping = field_term_grouping_of("foo", "bar")

            expect(term_grouping.composite_clause).to eq({"terms" => {
              "field" => "foo.bar"
            }})
          end

          it "uses the names of the fields in the index rather than the GraphQL query field names when they differ" do
            grouping = field_term_grouping_of("foo", "bar", field_names_in_graphql_query: ["oof", "rab"])

            expect(grouping.composite_clause.dig("terms", "field")).to eq("foo.bar")
          end

          it "merges in the provided grouping options" do
            grouping = field_term_grouping_of("foo", "bar")

            clause = grouping.composite_clause(grouping_options: {"optA" => 1, "optB" => false})

            expect(clause["terms"]).to include({"optA" => 1, "optB" => false})
          end
        end

        describe "#inner_meta" do
          it "returns inner meta" do
            grouping = field_term_grouping_of("foo", "bar")
            expect(grouping.inner_meta).to eq({
              "key_path" => [
                "key"
              ],
              "merge_into_bucket" => {}
            })
          end
        end
      end
    end
  end
end
