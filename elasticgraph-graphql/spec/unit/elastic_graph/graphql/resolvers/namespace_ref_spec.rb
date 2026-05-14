# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/namespace_ref"

module ElasticGraph
  class GraphQL
    module Resolvers
      RSpec.describe NamespaceRef, :resolver do
        attr_accessor :schema_artifacts

        before(:context) do
          self.schema_artifacts = generate_schema_artifacts do |schema|
            schema.namespace_type "OlapQuery"

            schema.on_root_query_type do |t|
              # Auto-wired to `:namespace_ref` since `OlapQuery` is a namespace type.
              t.field "olap", "OlapQuery!"
            end
          end
        end

        let(:graphql) { build_graphql(schema_artifacts: schema_artifacts) }
        subject(:resolver) { NamespaceRef.new(elasticgraph_graphql: graphql, config: {}) }

        it "returns an empty hash as a passthrough object for the namespace field" do
          expect(resolve("Query", "olap")).to eq({})
        end
      end
    end
  end
end
