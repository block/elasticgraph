# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/params"
require "elastic_graph/schema_artifacts/runtime_metadata/sourced_from_nested_path_segment"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # The result of resolving a relationship chain.
      #
      # @private
      class ResolvedRelationshipChain < Support::MemoizableData.define(
        :relationships,  # Array<Relationship> - every relationship in the chain, ordered root-to-leaf
        :path_segments   # Array<PathSegment> - the embedding fields to descend, ordered root-to-leaf
      )
        # The relationship the chain terminated at on the root indexed type.
        def root_relationship
          relationships.first
        end

        # The relationship the chain was resolved from — backs the `sourced_from` field(s).
        def leaf_relationship
          relationships.last
        end

        # The index the chain terminates at — where the root indexed type's documents (and their nested
        # elements) live, and where the chain's navigation path is registered. The chain always terminates at
        # an indexed type (enforced when it is resolved), so this is never `nil`.
        def root_index
          root_relationship.parent_type.index_def # : Index
        end

        # Records this chain's navigation path on its root index, so the painless script can locate the
        # nested element to update at index time.
        def register_on_root_index
          root_index.register_sourced_from_nested_paths(qualified_relationship, sourced_from_nested_paths)
        end

        # The leaf relationship name qualified by its embedding-field path (hence unique per resolved chain)
        def qualified_relationship
          @qualified_relationship ||=
            (path_segments.map { |segment| segment.field.name_in_index } + [leaf_relationship.name_in_index]).join(".")
        end

        # The runtime-metadata segments the painless script uses to navigate this chain: a `ListPathSegment` for
        # each list embedding field (carrying the source field that matches the element) and an `ObjectPathSegment`
        # for each object embedding field.
        def sourced_from_nested_paths
          @sourced_from_nested_paths ||= path_segments.map do |segment|
            if (source_field = segment.source_field_name)
              SchemaArtifacts::RuntimeMetadata::ListPathSegment.new(
                field: segment.field.name_in_index,
                source_field: source_field
              )
            else
              SchemaArtifacts::RuntimeMetadata::ObjectPathSegment.new(
                field: segment.field.name_in_index
              )
            end
          end
        end

        # The params identifying which nested element to update at each level: one entry per list segment,
        # pulling the matching value from the segment's foreign key on the source event. Object segments have no
        # ambiguity, so they contribute no identifier.
        def path_identifier_params
          @path_identifier_params ||= path_segments.filter_map do |segment|
            source_field = segment.source_field_name
            next unless source_field

            param = SchemaArtifacts::RuntimeMetadata::DynamicParam.new(source_path: source_field, cardinality: :one)
            [source_field, param]
          end.to_h
        end
      end
    end
  end
end
