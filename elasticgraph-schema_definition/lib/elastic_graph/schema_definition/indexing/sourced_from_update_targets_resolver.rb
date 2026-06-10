# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_definition/indexing/relationship_chain_resolver"
require "elastic_graph/schema_definition/indexing/relationship_resolver"
require "elastic_graph/schema_definition/indexing/update_target_resolver"

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
          fields_with_sources_by_relationship_name = sourced_fields_by_relationship_name(object_type)
          defined_relationships = object_type.relationships_by_name.keys

          results = (defined_relationships | fields_with_sources_by_relationship_name.keys).filter_map do |relationship_name|
            empty_fields = [] # : ::Array[SchemaElements::Field]
            sourced_fields = fields_with_sources_by_relationship_name.fetch(relationship_name) { empty_fields }
            relationship_resolver = RelationshipResolver.new(
              schema_def_state: @schema_def_state,
              object_type: object_type,
              relationship_name: relationship_name,
              sourced_fields: sourced_fields
            )

            resolved_relationship, relationship_error = relationship_resolver.resolve
            yield :relationship, relationship_error if relationship_error

            if object_type.own_index_def && resolved_relationship && sourced_fields.any?
              resolve_update_target(object_type, resolved_relationship, sourced_fields, &error_reporter)
            end
          end

          # Resolve any `parent_relationship` chains on this type, surfacing configuration errors and
          # registering the resolved path segments on the root index.
          resolve_relationship_chains(object_type, &error_reporter)

          results
        end

        def resolve_update_target(object_type, resolved_relationship, sourced_fields)
          update_target_resolver = UpdateTargetResolver.new(
            object_type: object_type,
            resolved_relationship: resolved_relationship,
            sourced_fields: sourced_fields,
            field_path_resolver: @schema_def_state.field_path_resolver
          )

          update_target, errors = update_target_resolver.resolve
          errors.each { |error| yield :sourced_field, error }

          # Validate that has_had_multiple_sources! has been called when sourced_from is used
          index_def = object_type.own_index_def # : Index
          unless index_def.has_had_multiple_sources_flag
            yield :sourced_field, "Type `#{object_type.name}` uses `sourced_from` fields but its index `#{index_def.name}` " \
              "has not been configured with `has_had_multiple_sources!`. To resolve this, add `i.has_had_multiple_sources!` within the " \
              "`t.index \"#{index_def.name}\"` block. This flag is required because indices with multiple sources can contain " \
              "incomplete documents, and ElasticGraph needs to know this to apply proper filtering. Once set, this flag should remain even " \
              "if you later remove all `sourced_from` fields, as the index may still contain historical incomplete documents."
          end

          [resolved_relationship.related_type.name, update_target] if update_target
        end

        def resolve_relationship_chains(object_type)
          relationships_with_parent_ref = object_type.relationships_by_name.each_value.select(&:parent_ref)
          return if relationships_with_parent_ref.empty?

          # The set of relationship names this type's `sourced_from` fields draw their data through. We use
          # `fields_with_sources` (rather than `sourced_fields_by_relationship_name`) because it works for
          # non-indexed (embedded) types — which is exactly where nested `sourced_from` fields live.
          relationship_names_with_sourced_fields = object_type.fields_with_sources.map { |f| (_ = f.source).relationship_name }.to_set

          chain_resolver = RelationshipChainResolver.new(schema_def_state: @schema_def_state)

          relationships_with_parent_ref.each do |relationship|
            # Every `parent_relationship` chain is resolved so its configuration errors are surfaced, even for
            # relationships that don't themselves back any `sourced_from` field.
            resolved_chain, chain_errors = chain_resolver.resolve(relationship)
            chain_errors.each { |error| yield :sourced_field, error }
            next unless resolved_chain

            # Only register paths for relationships that back `sourced_from` fields. A pure link in a longer
            # chain has no nested data of its own; its navigation lives in the leaf relationship's chain.
            next unless relationship_names_with_sourced_fields.include?(relationship.name)

            # Register the resolved chain on its root index, which records the path segments keyed by the
            # chain's qualified relationship.
            root_index = resolved_chain.root_relationship.parent_type.index_def # : Index
            root_index.register_resolved_relationship_chain(resolved_chain)
          end
        end

        def sourced_fields_by_relationship_name(object_type)
          if object_type.own_index_def.nil?
            # For now, only indexed types can have `sourced_from` fields, and resolving `fields_with_sources` on an unindexed union type
            # such as `_Entity` when we are using apollo can lead to exceptions when multiple entity types have the same field name
            # that use different mapping types.
            {} # : ::Hash[::String, ::Array[SchemaElements::Field]]
          else
            object_type
              .fields_with_sources
              .group_by { |f| (_ = f.source).relationship_name }
          end
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
