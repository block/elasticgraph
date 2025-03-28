# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/graphql_resolver"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe GraphQLResolver do
        it "loads a resolver dynamically" do
          resolver = GraphQLResolver.new(
            needs_lookahead: false,
            resolver_ref: {
              "extension_name" => "ElasticGraph::GraphQLResolver1",
              "require_path" => "elastic_graph/spec_support/example_extensions/graphql_resolvers"
            }
          )

          expect(resolver.load_resolver.extension_class).to be GraphQLResolver1
        end
      end
    end
  end
end
