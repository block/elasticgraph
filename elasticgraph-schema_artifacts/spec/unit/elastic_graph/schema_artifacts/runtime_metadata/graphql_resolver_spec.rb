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
        it "loads a resolver with lookahead dynamically" do
          resolver = GraphQLResolver.new(
            needs_lookahead: true,
            resolver_ref: {
              "name" => "ElasticGraph::GraphQLResolverWithLookahead",
              "require_path" => "elastic_graph/spec_support/example_extensions/graphql_resolvers"
            }
          )

          expect(resolver.load_resolver.extension_class).to be GraphQLResolverWithLookahead
        end

        it "loads a resolver without lookahead dynamically" do
          resolver = GraphQLResolver.new(
            needs_lookahead: false,
            resolver_ref: {
              "name" => "ElasticGraph::GraphQLResolverWithoutLookahead",
              "require_path" => "elastic_graph/spec_support/example_extensions/graphql_resolvers"
            }
          )

          expect(resolver.load_resolver.extension_class).to be GraphQLResolverWithoutLookahead
        end

        it "raises an error if `needs_lookahead` is true for a resolver without lookahead" do
          resolver = GraphQLResolver.new(
            needs_lookahead: true,
            resolver_ref: {
              "name" => "ElasticGraph::GraphQLResolverWithoutLookahead",
              "require_path" => "elastic_graph/spec_support/example_extensions/graphql_resolvers"
            }
          )

          expect {
            resolver.load_resolver
          }.to raise_error Errors::InvalidExtensionError
        end

        it "raises an error if `needs_lookahead` is false for a resolver with lookahead" do
          resolver = GraphQLResolver.new(
            needs_lookahead: false,
            resolver_ref: {
              "name" => "ElasticGraph::GraphQLResolverWithLookahead",
              "require_path" => "elastic_graph/spec_support/example_extensions/graphql_resolvers"
            }
          )

          expect {
            resolver.load_resolver
          }.to raise_error Errors::InvalidExtensionError
        end
      end
    end
  end
end
