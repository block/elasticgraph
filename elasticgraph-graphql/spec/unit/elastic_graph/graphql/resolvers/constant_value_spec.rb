# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/constant_value"

module ElasticGraph
  class GraphQL
    module Resolvers
      RSpec.describe ConstantValue, :resolver do
        attr_accessor :schema_artifacts

        before(:context) do
          self.schema_artifacts = generate_schema_artifacts do |schema|
            schema.on_root_query_type do |t|
              t.field "pi", "Float" do |f|
                f.resolve_with :constant_value, value: 3.141592654
              end

              t.field "sentinel", "String" do |f|
                f.resolve_with :constant_value, value: "placeholder"
              end
            end
          end
        end

        let(:graphql) { build_graphql(schema_artifacts: schema_artifacts) }

        context "when configured with a scalar value" do
          subject(:resolver) { ConstantValue.new(elasticgraph_graphql: graphql, config: {value: 3.141592654}) }

          it "returns the configured value, ignoring the field, args, and context" do
            expect(resolve("Query", "pi")).to eq 3.141592654
          end
        end

        context "when configured with an object reference" do
          let(:sentinel) { ::Object.new }
          subject(:resolver) { ConstantValue.new(elasticgraph_graphql: graphql, config: {value: sentinel}) }

          it "returns the same object reference" do
            expect(resolve("Query", "sentinel")).to be sentinel
          end
        end

        it "raises when `:value` is missing from `config`" do
          expect {
            ConstantValue.new(elasticgraph_graphql: graphql, config: {})
          }.to raise_error(KeyError, /value/)
        end
      end
    end
  end
end
