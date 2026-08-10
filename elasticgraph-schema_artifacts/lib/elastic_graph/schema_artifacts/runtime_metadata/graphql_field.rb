# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/configured_graphql_resolver"
require "elastic_graph/schema_artifacts/runtime_metadata/relation"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # @private
      class GraphQLField < ::Data.define(:name_in_index, :relation, :computation_function, :resolver)
        EMPTY = new(nil, nil, nil, nil)
        NAME_IN_INDEX = "name_in_index"
        RELATION = "relation"
        COMPUTATION_FUNCTION = "computation_function"
        RESOLVER = "resolver"

        def self.from_hash(hash)
          new(
            name_in_index: hash[NAME_IN_INDEX],
            relation: hash[RELATION]&.then { |rel_hash| Relation.from_hash(rel_hash) },
            computation_function: hash[COMPUTATION_FUNCTION]&.to_sym,
            resolver: hash[RESOLVER]&.then { |res_hash| ConfiguredGraphQLResolver.from_hash(res_hash) }
          )
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            COMPUTATION_FUNCTION => computation_function&.to_s,
            NAME_IN_INDEX => name_in_index,
            RELATION => relation&.to_dumpable_hash,
            RESOLVER => resolver&.to_dumpable_hash
          }
        end

        # Indicates if we need this field in our dumped runtime metadata, when it has the given
        # `name_in_graphql`. Fields that have not been customized in some way do not need to be
        # included in the dumped runtime metadata.
        def needed?(name_in_graphql)
          !!relation ||
            !!computation_function ||
            name_in_index&.!=(name_in_graphql) ||
            !resolver.nil? ||
            false
        end
      end
    end
  end
end
