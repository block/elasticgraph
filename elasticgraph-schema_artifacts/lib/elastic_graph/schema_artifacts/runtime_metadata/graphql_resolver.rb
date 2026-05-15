# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # @private
      class GraphQLResolver < ::Data.define(:needs_lookahead, :resolver_ref)
        def self.with_lookahead_loader
          @with_lookahead_loader ||= ExtensionLoader.new(InterfaceWithLookahead)
        end

        def self.without_lookahead_loader
          @without_lookahead_loader ||= ExtensionLoader.new(InterfaceWithoutLookahead)
        end

        NEEDS_LOOKAHEAD = "needs_lookahead"
        RESOLVER_REF = "resolver_ref"

        def load_resolver
          loader = needs_lookahead ? GraphQLResolver.with_lookahead_loader : GraphQLResolver.without_lookahead_loader
          Extension.load_from_hash(resolver_ref, via: loader)
        end

        # @param hash [Hash{String => Object}] serialized GraphQL resolver
        def self.from_hash(hash)
          new(
            needs_lookahead: hash.fetch(NEEDS_LOOKAHEAD),
            resolver_ref: hash.fetch(RESOLVER_REF)
          )
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            NEEDS_LOOKAHEAD => needs_lookahead,
            RESOLVER_REF => resolver_ref
          }
        end

        # @private
        class InterfaceWithLookahead
          # @param elasticgraph_graphql [ElasticGraph::GraphQL] GraphQL instance
          # @param config [Hash{Symbol => Object}] resolver configuration
          def initialize(elasticgraph_graphql:, config:)
            # must be defined, but nothing to do
          end

          # @param field [Object] GraphQL field being resolved
          # @param object [Object] parent object
          # @param args [Hash{Symbol => Object}] field arguments
          # @param context [Object] GraphQL context
          # @param lookahead [Object] lookahead into sub-selections
          def resolve(field:, object:, args:, context:, lookahead:)
          end
        end

        # @private
        class InterfaceWithoutLookahead
          # @param elasticgraph_graphql [ElasticGraph::GraphQL] GraphQL instance
          # @param config [Hash{Symbol => Object}] resolver configuration
          def initialize(elasticgraph_graphql:, config:)
            # must be defined, but nothing to do
          end

          # @param field [Object] GraphQL field being resolved
          # @param object [Object] parent object
          # @param args [Hash{Symbol => Object}] field arguments
          # @param context [Object] GraphQL context
          def resolve(field:, object:, args:, context:)
          end
        end
      end
    end
  end
end
