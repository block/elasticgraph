# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_definition/indexing/nested_relationship_chain_resolver"
require "elastic_graph/schema_definition/indexing/nested_update_target_resolver"
require "elastic_graph/schema_definition/indexing/relationship_resolver"
require "elastic_graph/schema_definition/indexing/update_target_resolver"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Resolves all `sourced_from` relationships across the schema into update targets,
      # keyed by the source type name that publishes the events.
      #
      # @private
      class SourcedUpdateTargetsResolver
        def initialize(schema_def_state:)
          @schema_def_state = schema_def_state
          @sourced_field_errors = [] # : ::Array[::String]
          @relationship_errors = [] # : ::Array[::String]
          @sourced_update_targets_by_type_name = ::Hash.new { |h, k| h[k] = [] } # : ::Hash[untyped, ::Array[SchemaArtifacts::RuntimeMetadata::UpdateTarget]]
        end

        # Returns a map of object type name → list of sourced update targets for that type.
        def resolve
          @schema_def_state.object_types_by_name.except(*@schema_def_state.namespace_types_by_name.keys).values.each do |object_type|
            resolve_for_type(object_type)
          end

          raise_if_errors
          @sourced_update_targets_by_type_name
        end

        private

        def resolve_for_type(object_type)
          fields_with_sources_by_relationship_name =
            if object_type.own_index_def.nil?
              # only indexed types can have `sourced_from` fields, and resolving `fields_with_sources` on an unindexed union type
              # such as `_Entity` when we are using apollo can lead to exceptions when multiple entity types have the same field name
              # that use different mapping types.
              {} # : ::Hash[::String, ::Array[SchemaElements::Field]]
            else
              object_type
                .fields_with_sources
                .group_by { |f| (_ = f.source).relationship_name }
            end

          defined_relationships = object_type.relationships_by_name.keys

          (defined_relationships | fields_with_sources_by_relationship_name.keys).each do |relationship_name|
            sourced_fields = fields_with_sources_by_relationship_name.fetch(relationship_name) { [] }
            relationship_resolver = RelationshipResolver.new(
              schema_def_state: @schema_def_state,
              object_type: object_type,
              relationship_name: relationship_name,
              sourced_fields: sourced_fields
            )

            resolved_relationship, relationship_error = relationship_resolver.resolve
            @relationship_errors << relationship_error if relationship_error

            if object_type.own_index_def && resolved_relationship && sourced_fields.any?
              resolve_top_level_update_target(object_type, resolved_relationship, sourced_fields)
            end
          end

          # Process nested sourced_from fields on non-indexed types.
          if object_type.own_index_def.nil?
            resolve_nested_update_targets(object_type)
          end
        end

        def resolve_top_level_update_target(object_type, resolved_relationship, sourced_fields)
          update_target_resolver = UpdateTargetResolver.new(
            object_type: object_type,
            resolved_relationship: resolved_relationship,
            sourced_fields: sourced_fields,
            field_path_resolver: @schema_def_state.field_path_resolver
          )

          update_target, errors = update_target_resolver.resolve
          @sourced_update_targets_by_type_name[resolved_relationship.related_type.name] << update_target if update_target
          @sourced_field_errors.concat(errors)

          # Validate that has_had_multiple_sources! has been called when sourced_from is used
          if (index_def = object_type.own_index_def) && !index_def.has_had_multiple_sources_flag
            @sourced_field_errors << "Type `#{object_type.name}` uses `sourced_from` fields but its index `#{index_def.name}` " \
              "has not been configured with `has_had_multiple_sources!`. To resolve this, add `i.has_had_multiple_sources!` within the " \
              "`t.index \"#{index_def.name}\"` block. This flag is required because indices with multiple sources can contain " \
              "incomplete documents, and ElasticGraph needs to know this to apply proper filtering. Once set, this flag should remain even " \
              "if you later remove all `sourced_from` fields, as the index may still contain historical incomplete documents."
          end
        end

        def resolve_nested_update_targets(object_type)
          nested_relationships = object_type.relationships_by_name
            .select { |_, rel| rel.parent_ref }

          return if nested_relationships.empty?

          fields_with_sources_by_relationship_name = object_type
            .indexing_fields_by_name_in_index.values
            .reject { |f| f.source.nil? }
            .group_by { |f| (_ = f.source).relationship_name }

          nested_relationships.each do |rel_name, relationship|
            empty_fields = [] # : ::Array[SchemaElements::Field]
            sourced_fields = fields_with_sources_by_relationship_name.fetch(rel_name) { empty_fields }

            next if sourced_fields.empty?

            chain_resolver = NestedRelationshipChainResolver.new(schema_def_state: @schema_def_state)
            resolved_chain, chain_errors = chain_resolver.resolve(relationship, object_type)

            if chain_errors.any?
              @sourced_field_errors.concat(chain_errors)
              next
            end

            resolved_chain = _ = resolved_chain # : ResolvedNestedChain
            resolver = NestedUpdateTargetResolver.new(
              object_type: object_type,
              relationship: relationship,
              sourced_fields: sourced_fields,
              resolved_chain: resolved_chain,
              field_path_resolver: @schema_def_state.field_path_resolver,
              schema_def_state: @schema_def_state
            )

            update_target, resolve_errors = resolver.resolve
            @sourced_field_errors.concat(resolve_errors)

            next unless update_target

            related_type_name = relationship.related_type.unwrap_non_null.name
            @sourced_update_targets_by_type_name[related_type_name] << update_target
          end
        end

        def raise_if_errors
          full_errors = [] # : ::Array[::String]

          if @sourced_field_errors.any?
            full_errors << "Schema had #{@sourced_field_errors.size} error(s) related to `sourced_from` fields:\n\n#{@sourced_field_errors.map.with_index(1) { |e, i| "#{i}. #{e}" }.join("\n\n")}"
          end

          if @relationship_errors.any?
            full_errors << "Schema had #{@relationship_errors.size} error(s) related to relationship fields:\n\n#{@relationship_errors.map.with_index(1) { |e, i| "#{i}. #{e}" }.join("\n\n")}"
          end

          unless full_errors.empty?
            raise Errors::SchemaError, full_errors.join("\n\n")
          end
        end
      end
    end
  end
end
