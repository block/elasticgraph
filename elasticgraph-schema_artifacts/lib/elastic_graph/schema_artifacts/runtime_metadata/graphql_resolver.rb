# Copyright 2024 - 2025 Block, Inc.
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
      class GraphQLResolver < ::Data.define(:needs_lookahead, :resolver_ref)
        def self.extension_loader
          @extension_loader ||= ExtensionLoader.new(Interface)
        end

        NEEDS_LOOKAHEAD = "needs_lookahead"
        RESOLVER_REF = "resolver_ref"

        def load_resolver
          Extension.load_from_hash(resolver_ref, via: GraphQLResolver.extension_loader)
        end

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

        class Interface
          def initialize(elasticgraph_graphql:, config:)
            # must be defined, but nothing to do
          end

          def resolve(field:, object:, args:, context:, lookahead:)
          end
        end
      end
    end
  end
end
