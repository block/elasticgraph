# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/function_adapter"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe FunctionAdapter do
        describe "BY_NAME" do
          it "registers an adapter for each supported aggregated value function" do
            expect(FunctionAdapter::BY_NAME.keys).to contain_exactly(:avg, :cardinality, :max, :min, :percentiles, :sum)
          end

          it "maps each function to its datastore aggregation name" do
            expect(FunctionAdapter::BY_NAME.transform_values(&:datastore_function_name)).to eq(
              avg: "avg",
              cardinality: "cardinality",
              max: "max",
              min: "min",
              percentiles: "percentiles",
              sum: "sum"
            )
          end

          it "fabricates the empty bucket response each function returns when the datastore has no documents to aggregate" do
            expect(FunctionAdapter::BY_NAME.transform_values(&:empty_bucket_result)).to eq(
              avg: {"value" => nil},
              cardinality: {"value" => 0},
              max: {"value" => nil},
              min: {"value" => nil},
              percentiles: {"values" => [{"value" => nil}]},
              sum: {"value" => 0}
            )
          end
        end

        describe FunctionAdapter::SimpleMetric do
          let(:element_names) { SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: :snake_case, overrides: {}) }
          let(:adapter) { FunctionAdapter::SimpleMetric.new(datastore_function_name: "avg", empty_bucket_value: nil) }

          it "exposes the datastore function name it was configured with" do
            expect(adapter.datastore_function_name).to eq "avg"
          end

          it "extracts no args, since these functions take none" do
            expect(adapter.extract_args({"some_arg" => 3}, element_names)).to eq({})
          end

          it "contributes no extra clause options beyond the `field` the clause builder provides" do
            expect(adapter.clause_options({})).to eq({})
          end

          it "returns the raw datastore response as the value hash, since these functions return a flat response" do
            expect(adapter.extract_result({"value" => 3.7})).to eq({"value" => 3.7})
          end

          it "fabricates an empty bucket response using the configured empty bucket value" do
            expect(adapter.empty_bucket_result).to eq({"value" => nil})
            expect(FunctionAdapter::SimpleMetric.new(datastore_function_name: "sum", empty_bucket_value: 0).empty_bucket_result).to eq({"value" => 0})
          end
        end

        describe FunctionAdapter::Percentile do
          let(:element_names) { SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: :snake_case, overrides: {}) }
          let(:adapter) { FunctionAdapter::Percentile.new(datastore_function_name: "percentiles") }

          it "exposes the datastore function name it was configured with" do
            expect(adapter.datastore_function_name).to eq "percentiles"
          end

          it "extracts the requested percentile rank from the args" do
            expect(adapter.extract_args({"percentile" => 50.0}, element_names)).to eq({percentile: 50.0})
          end

          it "accepts the boundary values 0 and 100" do
            expect(adapter.extract_args({"percentile" => 0}, element_names)).to eq({percentile: 0})
            expect(adapter.extract_args({"percentile" => 100}, element_names)).to eq({percentile: 100})
          end

          it "raises a GraphQL::ExecutionError when the requested percentile is below 0" do
            expect {
              adapter.extract_args({"percentile" => -1}, element_names)
            }.to raise_error(::GraphQL::ExecutionError, "`percentile` must be between 0 and 100, but is -1.")
          end

          it "raises a GraphQL::ExecutionError when the requested percentile is above 100" do
            expect {
              adapter.extract_args({"percentile" => 150}, element_names)
            }.to raise_error(::GraphQL::ExecutionError, "`percentile` must be between 0 and 100, but is 150.")
          end

          it "requests a single unkeyed percentile in the clause options" do
            expect(adapter.clause_options({percentile: 99.9})).to eq({"percents" => [99.9], "keyed" => false})
          end

          it "extracts the single value from the datastore's array-shaped response" do
            expect(adapter.extract_result({"values" => [{"key" => 50.0, "value" => 3.7}]})).to eq({"key" => 50.0, "value" => 3.7})
          end

          it "fabricates an empty bucket response with a nil value" do
            expect(adapter.empty_bucket_result).to eq({"values" => [{"value" => nil}]})
          end
        end
      end
    end
  end
end
