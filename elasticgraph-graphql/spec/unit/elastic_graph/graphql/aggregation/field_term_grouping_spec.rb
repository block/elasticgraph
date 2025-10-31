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
          it "returns inner meta without missing_values when no placeholder is provided" do
            grouping = field_term_grouping_of("foo", "bar", missing_value_placeholder: nil)
            expect(grouping.inner_meta).to eq({
              "key_path" => ["key"],
              "merge_into_bucket" => {}
            })
          end

          it "includes missing_value in inner meta when placeholder is provided" do
            grouping = field_term_grouping_of("foo", "bar", missing_value_placeholder: "MISSING")
            expect(grouping.inner_meta).to eq({
              "key_path" => ["key"],
              "merge_into_bucket" => {},
              "missing_values" => ["MISSING"]
            })
          end
        end

        describe "#missing_value_placeholder" do
          it "returns the placeholder value when provided" do
            grouping = field_term_grouping_of("foo", "bar", missing_value_placeholder: "MISSING")
            expect(grouping.missing_value_placeholder).to eq("MISSING")
          end

          it "returns nil when no placeholder is provided" do
            grouping = field_term_grouping_of("foo", "bar", missing_value_placeholder: nil)
            expect(grouping.missing_value_placeholder).to be_nil
          end
        end

        describe "#handles_missing_values?" do
          it "returns true when a placeholder is provided" do
            grouping = field_term_grouping_of("foo", "bar", missing_value_placeholder: "MISSING")
            expect(grouping.handles_missing_values?).to be(true)
          end

          it "returns false when no placeholder is provided" do
            grouping = field_term_grouping_of("foo", "bar", missing_value_placeholder: nil)
            expect(grouping.handles_missing_values?).to be(false)
          end
        end

        describe "#non_composite_clause_for" do
          let(:query) do
            aggregation_query_of(
              first: 11,
              needs_doc_count_error: true
            )
          end

          context "when a missing value placeholder is provided" do
            it "includes the missing parameter in the terms clause" do
              grouping = field_term_grouping_of("foo", "bar", missing_value_placeholder: "MISSING")
              clause = grouping.non_composite_clause_for(query)

              expect(clause).to eq({
                "terms" => {
                  "field" => "foo.bar",
                  "collect_mode" => "depth_first",
                  "missing" => "MISSING",
                  "size" => query.paginator.requested_page_size,
                  "show_term_doc_count_error" => true
                }
              })
            end
          end

          context "when no missing value placeholder is provided" do
            it "does not include the missing parameter in the terms clause" do
              grouping = field_term_grouping_of("foo", "bar", missing_value_placeholder: nil)
              clause = grouping.non_composite_clause_for(query)

              expect(clause).to eq({
                "terms" => {
                  "field" => "foo.bar",
                  "collect_mode" => "depth_first",
                  "size" => query.paginator.requested_page_size,
                  "show_term_doc_count_error" => true
                }
              })
            end
          end
        end
      end
    end
  end
end
