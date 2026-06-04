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
      # The result of resolving a relationship chain.
      #
      # @private
      ResolvedRelationshipChain = ::Data.define(
        :root_relationship,  # Relationship - the root relationship (no parent_relationship)
        :path_segments       # Array<PathSegment> - ordered root-to-leaf
      )

      # Describes how to navigate from a parent type into a nested child element.
      # For list fields, `match_field_name` and `source_field_name` identify which element
      # to update: the element where `element[match_field_name] == event[source_field_name]`.
      # For non-list (object) fields, these are nil since there's no ambiguity.
      #
      # @private
      PathSegment = ::Data.define(
        :field,             # Field - the field to navigate into at this level
        :match_field_name,  # String? - field name on the nested element to match against (nil for object fields)
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
        end

        # Resolves the chain starting from `starting_relationship` (which must have a `parent_ref`).
        #
        # Returns a tuple of [resolved_chain, errors].
        # If errors is non-empty, resolved_chain will be nil.
        def resolve(starting_relationship)
          errors = [] # : ::Array[::String]
          path_segments = [] # : ::Array[PathSegment]
          visited_relationships = Set[starting_relationship]

          # resolve_chain returns the chain's root relationship (the one with no parent_ref), or nil
          # if it hit an error walking the chain (in which case the error is already recorded).
          root_relationship = resolve_chain(starting_relationship, path_segments, errors, visited_relationships)
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
            root_relationship: root_relationship,
            path_segments: path_segments.reverse # reverse so root-to-leaf order
          )

          [resolved_chain, errors]
        end

        private

        # Recursively walks from leaf to root, building path segments in reverse. Returns the root
        # relationship (the one with no parent_ref) on success, or nil if an error was encountered.
        def resolve_chain(current_rel, path_segments, errors, visited_relationships)
          parent_ref = current_rel.parent_ref
          return current_rel unless parent_ref

          parent_rel = resolve_parent_ref(current_rel, parent_ref, errors, visited_relationships)
          return nil unless parent_rel

          build_path_segment(current_rel, parent_rel.parent_type, path_segments, errors)
          return nil if errors.any?

          visited_relationships.add(parent_rel)
          resolve_chain(parent_rel, path_segments, errors, visited_relationships)
        end

        # Resolves a parent_ref into the concrete parent relationship.
        # Returns the parent relationship on success, or appends to errors and returns nil.
        def resolve_parent_ref(current_rel, ref, errors, visited_relationships)
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

          if visited_relationships.include?(parent_rel)
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

        # Builds a PathSegment for the current level and appends it to path_segments.
        # Uses the explicitly specified field name if provided, otherwise auto-discovers it.
        def build_path_segment(current_rel, parent_type, path_segments, errors)
          parent_ref = current_rel.parent_ref # : SchemaElements::Relationship::ParentRef
          field = resolve_field(parent_ref, parent_type, current_rel, errors)
          return unless field

          # For list fields, `match_field_name` and `source_field_name` identify which element
          # to update. `match_field_name` is always "id" because ElasticGraph relationships join
          # on `id` via foreign keys. For non-list fields, these are nil since there's no ambiguity.
          path_segments << if field.type.list?
            PathSegment.new(
              field: field,
              match_field_name: "id",
              source_field_name: current_rel.foreign_key
            )
          else
            PathSegment.new(
              field: field,
              match_field_name: nil,
              source_field_name: nil
            )
          end
        end

        def resolve_field(parent_ref, parent_type, current_rel, errors)
          if parent_ref.field_name
            field = parent_type.graphql_fields_by_name[parent_ref.field_name]
            unless field
              errors << "#{rel_description(current_rel)} references field `#{parent_type.name}.#{parent_ref.field_name}` " \
                "via `parent_relationship`, but that field does not exist."
            end
            field
          else
            find_field_by_type(parent_type, current_rel, errors)
          end
        end

        def find_field_by_type(parent_type, current_rel, errors)
          child_type = current_rel.parent_type
          matches = parent_type.graphql_fields_by_name.values.select do |field|
            field.type.fully_unwrapped.name == child_type.name
          end

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
