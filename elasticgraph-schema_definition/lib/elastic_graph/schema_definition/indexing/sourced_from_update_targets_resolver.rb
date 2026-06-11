# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_definition/indexing/nested_update_target_resolver"
require "elastic_graph/schema_definition/indexing/relationship_chain_resolver"
require "elastic_graph/schema_definition/indexing/relationship_resolver"
require "elastic_graph/schema_definition/indexing/top_level_update_target_resolver"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Resolves all `sourced_from` field declarations across the schema into update targets,
      # keyed by the source type name that publishes the events.
      #
      # @private
      class SourcedFromUpdateTargetsResolver
        def initialize(schema_def_state)
          @schema_def_state = schema_def_state
        end

        # Returns a map of source type name → update targets that should be triggered by that type's events.
        def resolve
          sourced_field_errors = [] # : ::Array[::String]
          relationship_errors = [] # : ::Array[::String]

          type_names_and_update_targets =
            @schema_def_state.object_types_by_name.except(*@schema_def_state.namespace_types_by_name.keys).each_value.flat_map do |object_type|
              resolve_for_type(object_type) do |error_type, error|
                errors = (error_type == :relationship) ? relationship_errors : sourced_field_errors
                errors << error
              end
            end

          raise_if_errors(sourced_field_errors, relationship_errors)

          type_names_and_update_targets
            .group_by(&:first)
            .transform_values { |pairs| pairs.map(&:last) }
        end

        private

        def resolve_for_type(object_type, &error_reporter)
          resolve_top_level_update_targets(object_type, &error_reporter) +
            resolve_nested_update_targets(object_type, &error_reporter)
        end

        # Resolves the update targets for this type's own `sourced_from` fields (the non-nested case): one per
        # relationship that backs `sourced_from` fields, each keyed by the related type that publishes the events.
        def resolve_top_level_update_targets(object_type, &error_reporter)
          # Skip unindexed types: they produce no top-level targets, and resolving `fields_with_sources` on an
          # unindexed apollo `_Entity` union can raise when entity types share a field name across mapping types.
          empty_fields_by_relationship = {} # : ::Hash[::String, ::Array[SchemaElements::Field]]
          sourced_fields_by_relationship_name =
            object_type.own_index_def ? group_sourced_fields_by_relationship_name(object_type) : empty_fields_by_relationship
          defined_relationships = object_type.relationships_by_name.keys

          (defined_relationships | sourced_fields_by_relationship_name.keys).filter_map do |relationship_name|
            empty_fields = [] # : ::Array[SchemaElements::Field]
            sourced_fields = sourced_fields_by_relationship_name.fetch(relationship_name) { empty_fields }
            relationship_resolver = RelationshipResolver.new(
              schema_def_state: @schema_def_state,
              object_type: object_type,
              relationship_name: relationship_name,
              sourced_fields: sourced_fields
            )

            resolved_relationship, relationship_error = relationship_resolver.resolve
            yield :relationship, relationship_error if relationship_error

            if object_type.own_index_def && resolved_relationship && sourced_fields.any?
              resolve_top_level_update_target(object_type, resolved_relationship, sourced_fields, &error_reporter)
            end
          end
        end

        # Resolves the update targets for this type's nested `sourced_from` fields: each `parent_relationship`
        # chain that backs `sourced_from` fields registers its navigation path on the root index and produces a
        # nested update target on the root indexed type.
        def resolve_nested_update_targets(object_type, &error_reporter)
          resolve_sourced_fields_and_chains(object_type, &error_reporter).filter_map do |sourced_fields, resolved_chain|
            resolved_chain.register_on_root_index
            resolve_nested_update_target(object_type, sourced_fields, resolved_chain, &error_reporter)
          end
        end

        def resolve_top_level_update_target(object_type, resolved_relationship, sourced_fields)
          top_level_update_target_resolver = TopLevelUpdateTargetResolver.new(
            object_type: object_type,
            resolved_relationship: resolved_relationship,
            sourced_fields: sourced_fields,
            field_path_resolver: @schema_def_state.field_path_resolver
          )

          update_target, errors = top_level_update_target_resolver.resolve
          errors.each { |error| yield :sourced_field, error }

          [resolved_relationship.related_type.name, update_target] if update_target
        end

        def group_sourced_fields_by_relationship_name(object_type)
          object_type.fields_with_sources.group_by { |f| (_ = f.source).relationship_name }
        end

        # Resolves every `parent_relationship` chain on this type, surfacing configuration errors. Returns
        # `[sourced_fields, resolved_chain]` for each chain that resolved cleanly *and* backs `sourced_from`
        # fields — the pairings that produce nested update targets.
        def resolve_sourced_fields_and_chains(object_type)
          relationships_with_parent_ref = object_type.relationships_by_name.each_value.select(&:parent_ref)
          empty_results = [] # : ::Array[[::Array[SchemaElements::Field], ResolvedRelationshipChain]]
          return empty_results if relationships_with_parent_ref.empty?

          sourced_fields_by_relationship_name = group_sourced_fields_by_relationship_name(object_type)

          relationships_with_parent_ref.filter_map do |relationship|
            # Resolve every chain (even those backing no `sourced_from` field) so configuration errors surface.
            resolved_chain, chain_errors = relationship_chain_resolver.resolve(relationship)
            chain_errors.each { |error| yield :sourced_field, error }
            next unless resolved_chain

            # Only chains backing `sourced_from` fields produce a target; pure links carry no nested data.
            sourced_fields = sourced_fields_by_relationship_name[relationship.name]
            [sourced_fields, resolved_chain] if sourced_fields
          end
        end

        # A single resolver shared across all object types so its per-parent-type field cache survives the
        # whole resolve pass — parent types recur across chains from different leaf types.
        def relationship_chain_resolver
          @relationship_chain_resolver ||= RelationshipChainResolver.new(schema_def_state: @schema_def_state)
        end

        def resolve_nested_update_target(object_type, sourced_fields, resolved_chain)
          nested_update_target_resolver = NestedUpdateTargetResolver.new(
            object_type: object_type,
            sourced_fields: sourced_fields,
            resolved_chain: resolved_chain,
            field_path_resolver: @schema_def_state.field_path_resolver,
            schema_def_state: @schema_def_state
          )

          update_target, errors = nested_update_target_resolver.resolve
          errors.each { |error| yield :sourced_field, error }

          # The update target lives on the source type — its events drive updates to the nested element.
          [resolved_chain.leaf_relationship.related_type.name, update_target] if update_target
        end

        def raise_if_errors(sourced_field_errors, relationship_errors)
          full_errors = [] # : ::Array[::String]

          if sourced_field_errors.any?
            full_errors << "Schema had #{sourced_field_errors.size} error(s) related to `sourced_from` fields:\n\n#{sourced_field_errors.map.with_index(1) { |e, i| "#{i}. #{e}" }.join("\n\n")}"
          end

          if relationship_errors.any?
            full_errors << "Schema had #{relationship_errors.size} error(s) related to relationship fields:\n\n#{relationship_errors.map.with_index(1) { |e, i| "#{i}. #{e}" }.join("\n\n")}"
          end

          unless full_errors.empty?
            raise Errors::SchemaError, full_errors.join("\n\n")
          end
        end
      end
    end
  end
end
