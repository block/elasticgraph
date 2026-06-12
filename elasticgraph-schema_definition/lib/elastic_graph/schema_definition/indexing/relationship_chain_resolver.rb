# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_definition/indexing/resolved_relationship_chain"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Describes how to navigate from a parent type into a nested child element.
      # For list fields, `source_field_name` identifies which element to update: the element
      # whose `id` matches `event[source_field_name]`. We implicitly match on the `id` field
      # because ElasticGraph relationships always join on `id` via foreign keys; this could be
      # made configurable in the future to support non-`id` primary keys.
      # For non-list (object) fields, `source_field_name` is nil since there's no ambiguity.
      #
      # @private
      PathSegment = ::Data.define(
        :field,             # Field - the field to navigate into at this level
        :source_field_name  # String? - field name on the source event providing the match value (nil for object fields)
      )

      # Resolves a chain of `parent_relationship` links from a leaf embedded type up to the
      # root indexed type. Produces a `ResolvedRelationshipChain` on success, or errors
      # describing what's invalid.
      #
      # @private
      class RelationshipChainResolver
        def initialize(schema_def_state:)
          @schema_def_state = schema_def_state

          # Lazily groups each parent type's indexing fields by their fully-unwrapped field type name,
          # so `find_field_by_type` can look up candidate embedding fields without re-scanning per chain.
          @indexing_fields_by_field_type_name_by_parent_type = ::Hash.new do |hash, parent_type|
            hash[parent_type] = parent_type.indexing_fields_by_name_in_index.values.group_by do |field|
              field.type.fully_unwrapped.name
            end
          end
        end

        # Resolves the chain starting from `starting_relationship` (which must have a `parent_ref`).
        #
        # Returns a tuple of [resolved_chain, errors].
        # If errors is non-empty, resolved_chain will be nil.
        def resolve(starting_relationship)
          errors = [] # : ::Array[::String]
          path_segments = [] # : ::Array[PathSegment]
          relationships = [] # : ::Array[SchemaElements::Relationship]

          # resolve_chain returns the chain's root relationship (the one with no parent_ref), or nil
          # if it hit an error walking the chain (in which case the error is already recorded).
          root_relationship = resolve_chain(starting_relationship, path_segments, relationships, errors)
          return [nil, errors] unless root_relationship

          # A valid chain must terminate at a relationship defined on an indexed type.
          root_type = root_relationship.parent_type
          unless root_type.root_document_type?
            errors << "The `parent_relationship` chain from #{rel_description(starting_relationship)} " \
              "terminates at `#{root_type.name}`, but `#{root_type.name}` is not an indexed type. " \
              "The chain must terminate at an indexed type."
            return [nil, errors]
          end

          resolved_chain = ResolvedRelationshipChain.new(
            relationships: relationships.reverse, # reverse so root-to-leaf order
            path_segments: path_segments.reverse # reverse so root-to-leaf order
          )

          [resolved_chain, errors]
        end

        private

        # Recursively walks from leaf to root, collecting relationships and their path segments (leaf-to-root;
        # `resolve` reverses both to root-to-leaf). Returns the root relationship (the one with no parent_ref) on
        # success, or nil if an error was encountered.
        def resolve_chain(current_rel, path_segments, relationships, errors)
          relationships << current_rel

          parent_ref = current_rel.parent_ref
          return current_rel unless parent_ref

          parent_rel = resolve_parent_ref(current_rel, parent_ref, relationships, errors)
          return nil unless parent_rel

          append_path_segments(current_rel, parent_rel.parent_type, path_segments, errors)
          return nil if errors.any?

          resolve_chain(parent_rel, path_segments, relationships, errors)
        end

        # Resolves a parent_ref into the concrete parent relationship.
        # Returns the parent relationship on success, or appends to errors and returns nil.
        def resolve_parent_ref(current_rel, ref, relationships, errors)
          unless current_rel.indexing_only
            errors << "#{rel_description(current_rel)} uses `parent_relationship` but is not declared with " \
              "`indexing_only: true`. Relationships with `parent_relationship` must be indexing-only."
            return nil
          end

          parent_type = ref.type_ref.as_object_type # : SchemaElements::ObjectType?
          unless parent_type
            errors << "#{rel_description(current_rel)} references parent type " \
              "`#{ref.type_ref.name}` via `parent_relationship`, but that type does not exist. Is it misspelled?"
            return nil
          end

          parent_rel = parent_type.relationships_by_name[ref.relationship_name]
          unless parent_rel
            errors << "#{rel_description(current_rel)} references parent relationship " \
              "`#{parent_type.name}.#{ref.relationship_name}` via `parent_relationship`, " \
              "but that relationship does not exist. Is it misspelled?"
            return nil
          end

          if relationships.include?(parent_rel)
            errors << "#{rel_description(current_rel)} creates a circular `parent_relationship` chain " \
              "— `#{parent_type.name}.#{ref.relationship_name}` was already visited. The chain must terminate at a root indexed type."
            return nil
          end

          current_source_type_name = current_rel.related_type.name
          parent_source_type_name = parent_rel.related_type.name
          unless current_source_type_name == parent_source_type_name
            errors << "#{rel_description(current_rel)} relates to `#{current_source_type_name}`, " \
              "but its parent relationship `#{parent_type.name}.#{ref.relationship_name}` relates to " \
              "`#{parent_source_type_name}`. All relationships in a `parent_relationship` chain must relate to the same source type."
            return nil
          end

          parent_rel
        end

        # Builds this link's PathSegment(s) and appends them to path_segments. The embedding field may be a dotted
        # path through intermediate object fields, so each path component becomes a segment.
        # Only the final field, when a list, identifies which element to update: it carries the relationship's
        # foreign key, matched against the element's `id`. A list before the final field would need its own match
        # value that a single link can't supply, so it's rejected.
        def append_path_segments(current_rel, parent_type, path_segments, errors)
          *leading_fields, leaf_field = resolve_embedding_fields(current_rel, parent_type, errors)
          return unless leaf_field

          if (intermediate_list = leading_fields.find { |field| field.type.list? })
            errors << "#{rel_description(current_rel)} embeds through list field `#{parent_type.name}.#{intermediate_list.name}` " \
              "via `parent_relationship`, but only the final embedding field may be a list. To source through an " \
              "intermediate list, give its embedded type its own `relates_to_one`/`relates_to_many` to the source " \
              "type with a `parent_relationship`, so that list level is matched by its own foreign key."
            return
          end

          leaf_foreign_key = current_rel.foreign_key if leaf_field.type.list?
          link_segments =
            leading_fields.map { |field| PathSegment.new(field: field, source_field_name: nil) } +
            [PathSegment.new(field: leaf_field, source_field_name: leaf_foreign_key)]

          # `resolve_chain` walks leaf-to-root and reverses the whole list once at the end, so append this link's
          # segments reversed for that final reverse to restore root-to-leaf order within the link.
          path_segments.concat(link_segments.reverse)
        end

        # Resolves this link's embedding field(s) on `parent_type`, one per dotted-path component. An explicit
        # `parent_field_name` is resolved by public name (consistent with `sourced_from` and `equivalent_field`);
        # the resolved `name_in_index` is what flows into the qualified relationship and the painless script.
        # Returns `[]` (and records an error) when it doesn't resolve.
        def resolve_embedding_fields(current_rel, parent_type, errors)
          parent_ref = current_rel.parent_ref # : SchemaElements::Relationship::ParentRef
          field_name = parent_ref.field_name
          return [find_field_by_type(parent_type, current_rel, errors)].compact unless field_name

          field_path = @schema_def_state.field_path_resolver.resolve_public_path(parent_type, field_name) { true }
          unless field_path
            errors << "#{rel_description(current_rel)} references field `#{parent_type.name}.#{field_name}` " \
              "via `parent_relationship`, but that field does not exist."
            return [] # : ::Array[SchemaElements::Field]
          end
          field_path.path_parts
        end

        def find_field_by_type(parent_type, current_rel, errors)
          child_type = current_rel.parent_type
          matches = @indexing_fields_by_field_type_name_by_parent_type.dig(parent_type, child_type.name) || []

          if matches.size > 1
            field_names = matches.map(&:name).join(", ")
            parent_ref = current_rel.parent_ref # : SchemaElements::Relationship::ParentRef
            errors << "#{rel_description(current_rel)} has an ambiguous `parent_relationship` — " \
              "`#{parent_type.name}` has multiple fields of type `#{child_type.name}` (#{field_names}). " \
              "Specify which field using the `parent_field_name:` option: " \
              "`r.parent_relationship \"#{parent_type.name}\", \"#{parent_ref.relationship_name}\", parent_field_name: \"<field_name>\"`"
            nil
          elsif matches.empty?
            errors << "#{rel_description(current_rel)} declares `#{parent_type.name}` as its parent type " \
              "via `parent_relationship`, but `#{parent_type.name}` has no field of type `#{child_type.name}`."
            nil
          else
            matches.first
          end
        end

        def rel_description(relationship)
          "`#{relationship.parent_type.name}.#{relationship.name}`"
        end
      end
    end
  end
end
