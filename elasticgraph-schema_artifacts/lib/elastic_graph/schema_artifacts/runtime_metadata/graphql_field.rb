# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/computation_detail"
require "elastic_graph/schema_artifacts/runtime_metadata/relation"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      class GraphQLField < ::Data.define(:name_in_index, :relation, :computation_detail, :resolver)
        EMPTY = new(nil, nil, nil, nil)
        NAME_IN_INDEX = "name_in_index"
        RELATION = "relation"
        AGGREGATION_DETAIL = "computation_detail"
        RESOLVER = "resolver"

        def self.from_hash(hash)
          new(
            name_in_index: hash[NAME_IN_INDEX],
            relation: hash[RELATION]&.then { |rel_hash| Relation.from_hash(rel_hash) },
            computation_detail: hash[AGGREGATION_DETAIL]&.then { |agg_hash| ComputationDetail.from_hash(agg_hash) },
            resolver: hash[RESOLVER]&.to_sym
          )
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            AGGREGATION_DETAIL => computation_detail&.to_dumpable_hash,
            NAME_IN_INDEX => name_in_index,
            RELATION => relation&.to_dumpable_hash,
            RESOLVER => resolver&.to_s
          }
        end

        # Indicates if we need this field in our dumped runtime metadata, when it has the given
        # `name_in_graphql`. Fields that have not been customized in some way do not need to be
        # included in the dumped runtime metadata.
        def needed?(name_in_graphql)
          !!relation ||
            !!computation_detail ||
            name_in_index&.!=(name_in_graphql) ||
            !resolver.nil? ||
            false
        end

        def with_computation_detail(empty_bucket_value:, function:)
          with(computation_detail: ComputationDetail.new(
            empty_bucket_value: empty_bucket_value,
            function: function
          ))
        end
      end
    end
  end
end
