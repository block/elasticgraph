# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/computation"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe Computation do
        include AggregationsHelpers

        describe "#key" do
          it "returns the computed field name prefixed with the field path and the aggregation name" do
            computation = computation_of("foo", "bar", :avg, computed_field_name: "average")

            expect(computation.key(aggregation_name: "my_aggs")).to eq aggregated_value_key_of("foo", "bar", "average", aggregation_name: "my_aggs").encode
          end

          it "uses GraphQL query field names when they differ from the name of the field in the index" do
            computation = computation_of("foo", "bar", :avg, computed_field_name: "average", field_names_in_graphql_query: ["oof", "rab"])

            expect(computation.key(aggregation_name: "my_aggs")).to eq aggregated_value_key_of("oof", "rab", "average", aggregation_name: "my_aggs").encode
          end

          it "uses the leaf's GraphQL query alias rather than its name in the index" do
            computation = computation_of("foo", "bar", :min, computed_field_name: "exact_min", leaf_alias: "myMin")

            expect(computation.key(aggregation_name: "my_aggs")).to eq aggregated_value_key_of("foo", "bar", "myMin", aggregation_name: "my_aggs").encode
          end

          it "differs between two aliases of the same function under the same field, so they don't collapse into one computation" do
            computation = computation_of("foo", :min, computed_field_name: "exact_min", leaf_alias: "exactMin")
            aliased_computation = computation_of("foo", :min, computed_field_name: "exact_min", leaf_alias: "myMin")

            expect(computation).not_to eq(aliased_computation)
            expect(computation.key(aggregation_name: "my_aggs")).not_to eq(aliased_computation.key(aggregation_name: "my_aggs"))
          end
        end

        describe "#clause" do
          it 'builds a datastore aggregation computation clause in the form: {function => {"field" => field_name}}' do
            computation = computation_of("foo", "bar", :avg)

            expect(computation.clause).to eq({"avg" => {"field" => "foo.bar"}})
          end

          it "uses the names of the fields in the index rather than the GraphQL query field names when they differ" do
            computation = computation_of("foo", "bar", :avg, field_names_in_graphql_query: ["oof", "rab"])

            expect(computation.clause).to eq({"avg" => {"field" => "foo.bar"}})
          end

          it "allows a `name_in_index` that references a child field" do
            computation = computation_of("foo.c", "bar.d", :avg, field_names_in_graphql_query: ["oof", "rab"])

            expect(computation.clause).to eq({"avg" => {"field" => "foo.c.bar.d"}})
          end

          it "is unaffected by an alias on the leaf" do
            computation = computation_of("foo", "bar", :avg, computed_field_name: "approximate_avg", leaf_alias: "myAvg")

            expect(computation.clause).to eq({"avg" => {"field" => "foo.bar"}})
          end
        end
      end
    end
  end
end
