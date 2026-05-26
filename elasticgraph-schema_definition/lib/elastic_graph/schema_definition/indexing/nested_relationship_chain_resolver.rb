# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Resolves a chain of `parent_relationship` links from a leaf embedded type up to the
      # root indexed type. Produces a `ResolvedNestedChain` describing the nested path and
      # match fields at each level.
      #
      # @private
      class NestedRelationshipChainResolver
        def initialize(schema_def_state:)
          @schema_def_state = schema_def_state
        end

        # Resolves the chain starting from `starting_relationship` (which must have a
        # `parent_relationship_config`) on `starting_type`.
        #
        # Returns a tuple of [resolved_chain, errors].
        # If errors is non-empty, resolved_chain will be nil.
        def resolve(starting_relationship, starting_type)
          errors = [] # : ::Array[::String]
          chain = [] # : ::Array[PathSegment]
          current_rel = starting_relationship
          current_type = starting_type
          visited_types = ::Set.new([starting_type.name])

          # Walk from leaf to root, building path segments in reverse. Each iteration validates
          # the current relationship's parent_relationship link and advances up one level.
          while current_rel.parent_relationship_config
            config = current_rel.parent_relationship_config

            # Validate that parent_relationship is used with indexing_only
            unless current_rel.indexing_only
              errors << "#{rel_description(current_type, current_rel)} uses `parent_relationship` but is not declared with " \
                "`indexing_only: true`. Relationships with `parent_relationship` must be indexing-only."
              break
            end

            # Detect circular chains
            if visited_types.include?(config[:parent_type_name])
              errors << "#{rel_description(current_type, current_rel)} creates a circular `parent_relationship` chain " \
                "— `#{config[:parent_type_name]}` was already visited. The chain must terminate at a root indexed type."
              break
            end

            # Find the parent type
            parent_type = @schema_def_state.object_types_by_name[config[:parent_type_name]]
            unless parent_type
              errors << "#{rel_description(current_type, current_rel)} references parent type " \
                "`#{config[:parent_type_name]}` via `parent_relationship`, but that type does not exist."
              break
            end

            # Find the parent relationship
            parent_rel = parent_type.relationships_by_name[config[:parent_relationship_name]]
            unless parent_rel
              errors << "#{rel_description(current_type, current_rel)} references parent relationship " \
                "`#{parent_type.name}.#{config[:parent_relationship_name]}` via `parent_relationship`, " \
                "but that relationship does not exist. Is it misspelled?"
              break
            end

            # Validate both relationships target the same source type
            current_source_type_name = current_rel.related_type.unwrap_non_null.name
            parent_source_type_name = parent_rel.related_type.unwrap_non_null.name
            unless current_source_type_name == parent_source_type_name
              errors << "#{rel_description(current_type, current_rel)} relates to `#{current_source_type_name}`, " \
                "but its parent relationship `#{parent_type.name}.#{config[:parent_relationship_name]}` relates to " \
                "`#{parent_source_type_name}`. All relationships in a `parent_relationship` chain must relate to the same source type."
              break
            end

            # Find the embedding field (field on parent_type whose type is current_type)
            embedding_field = find_embedding_field(parent_type, current_type, errors)
            unless embedding_field
              break if errors.any?
              errors << "#{rel_description(current_type, current_rel)} declares `#{parent_type.name}` as its parent type " \
                "via `parent_relationship`, but `#{parent_type.name}` has no field of type `#{current_type.name}`."
              break
            end

            # For list segments, validate that the embedded type has an `id` field to match on.
            if embedding_field.type.list?
              unless current_type.indexing_fields_by_name_in_index["id"]
                errors << "#{rel_description(current_type, current_rel)} requires an `id` field on `#{current_type.name}` " \
                  "for nested element matching, but `#{current_type.name}` has no field named `id`."
                break
              end
            end

            source_field_name = current_rel.foreign_key

            # We use "id" as the match field, consistent with how ElasticGraph relationships always join on `id`
            # via foreign keys. In the future, it would be nice if this field name were configurable. Additionally, the
            # composite key separator ":" in the Painless script assumes id values do not contain that character.
            # It would be nice to explicitly guard against that somehow.
            chain << PathSegment.new(
              parent_type: parent_type,
              embedding_field: embedding_field,
              match_field: "id",
              source_field: source_field_name
            )

            # Move up the chain
            current_rel = parent_rel
            current_type = parent_type
            visited_types.add(parent_type.name)
          end

          return [nil, errors] if errors.any?

          # The loop terminated because current_rel has no parent_relationship_config —
          # this is the root relationship. Validate that current_type is indexed.
          unless current_type.root_document_type?
            errors << "The `parent_relationship` chain from #{rel_description(starting_type, starting_relationship)} " \
              "terminates at `#{current_type.name}`, but `#{current_type.name}` is not an indexed type. " \
              "The chain must terminate at an indexed type."
            return [nil, errors]
          end

          resolved_chain = ResolvedNestedChain.new(
            root_indexed_type: current_type,
            path_segments: chain.reverse, # reverse so root-to-leaf order
            root_relationship: current_rel
          )

          [resolved_chain, errors]
        end

        private

        def find_embedding_field(parent_type, child_type, errors)
          matches = parent_type.graphql_fields_by_name.values.select do |field|
            field.type.fully_unwrapped.name == child_type.name
          end

          if matches.size > 1
            field_names = matches.map(&:name).join(", ")
            errors << "`#{parent_type.name}` has multiple fields of type `#{child_type.name}` (#{field_names}). " \
              "Ambiguous embedding path for `parent_relationship` — cannot determine which field to use."
            nil
          else
            matches.first
          end
        end

        def rel_description(type, relationship)
          "`#{type.name}.#{relationship.name}`"
        end
      end

      # The result of resolving a nested relationship chain.
      #
      # @private
      ResolvedNestedChain = ::Data.define(
        :root_indexed_type,  # ObjectType - the indexed type at the root
        :path_segments,      # Array<PathSegment> - ordered root-to-leaf
        :root_relationship   # Relationship - the root relationship (no parent_relationship)
      )

      # A single segment of the nested path.
      #
      # @private
      PathSegment = ::Data.define(
        :parent_type,      # ObjectType - the parent type at this level
        :embedding_field,  # Field - the field on parent_type that embeds the child type
        :match_field,      # String - field on the nested type to match (e.g., "id")
        :source_field      # String - field on the source type with the match value (from `via`)
      )
    end
  end
end
