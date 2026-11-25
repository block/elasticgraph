# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../../elasticgraph-graphql/spec/acceptance/elasticgraph_graphql_acceptance_support"
require_relative "graphql_benchmark"
require_relative "verify_indices"

module ElasticGraph
  RSpec.describe GraphQLRetrievalBenchmark, :builds_graphql do
    include_context "ElasticGraph GraphQL acceptance support"

    with_both_casing_forms do
      it "verifies the actual generated indices and rollover template with the configured client" do
        report = FieldRetrievalIndexVerification.verify(graphql.datastore_core)
        expect(report.fetch("checks")).not_to be_empty
        expect(report.fetch("checks").flat_map { |check| check.fetch("problems") }).to eq []
        expect(report.fetch("compatible")).to be true
        expect(report.fetch("data_parity_verified")).to be false
      end

      it "runs the end-to-end comparison harness and distinguishes fallback queries" do
        index_records(build(:widget, name: "example", amount_cents: 0))
        instances = GraphQLRetrievalBenchmark.instances(graphql)
        scalar = GraphQLRetrievalBenchmark.measure(instances, "{ widgets { nodes { id name } } }", warmup: 1, iterations: 2)
        mixed = GraphQLRetrievalBenchmark.measure(instances, "{ widgets { nodes { name tags } } }", warmup: 1, iterations: 2)
        expect(scalar.fetch("automatic_path_exercised")).to be true
        expect(mixed.fetch("automatic_path_exercised")).to be false
        expect(scalar.dig("variants", "automatic", "samples_ms").size).to eq 2
      end
    end
  end
end
