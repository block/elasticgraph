# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/params"
require "elastic_graph/schema_artifacts/runtime_metadata/sourced_from_nested_params"
require "elastic_graph/schema_definition/indexing/update_target_factory"
require "elastic_graph/schema_definition/indexing/update_target_resolver_support"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Resolves a relationship and a set of `sourced_from` fields into an `UpdateTarget` that instructs the
      # indexer how to update a type from the related type's source events. This handles the *nested* case,
      # where the `sourced_from` fields live on a type embedded within an indexed type (reached via a
      # `parent_relationship` chain) and the target updates the root indexed type the embedded type nests
      # within. (The *top-level* case—`sourced_from` fields directly on an indexed type—is handled by
      # `TopLevelUpdateTargetResolver`.)
      #
      # @private
      class NestedUpdateTargetResolver
        def initialize(
          object_type:,
          sourced_fields:,
          resolved_chain:,
          field_path_resolver:,
          schema_def_state:
        )
          @object_type = object_type
          @sourced_fields = sourced_fields
          @resolved_chain = resolved_chain
          @field_path_resolver = field_path_resolver
          @schema_def_state = schema_def_state
        end

        # Resolves the chain and `sourced_fields` into an `UpdateTarget` on the root indexed type,
        # validating everything along the way.
        #
        # Returns a tuple of the `update_target` (if valid) and a list of errors.
        def resolve
          relationship_errors = validate_relationships
          field_params, field_params_errors = UpdateTargetResolverSupport.resolve_sourced_field_params(
            object_type: object_type,
            related_type: related_type,
            sourced_fields: sourced_fields,
            field_path_resolver: field_path_resolver
          )
          routing_value_source, routing_error = resolve_field_source(UpdateTargetResolverSupport::RoutingSourceAdapter)
          rollover_timestamp_value_source, rollover_timestamp_error = resolve_field_source(UpdateTargetResolverSupport::RolloverTimestampSourceAdapter)
          # Routing/rollover values resolve from `equivalent_field`s on the root relationship, so they are
          # validated there (matching how `TopLevelUpdateTargetResolver` validates its own relationship).
          equivalent_field_errors = root_relationship.validate_equivalent_fields(field_path_resolver)
          has_had_multiple_sources_errors = UpdateTargetResolverSupport.validate_has_had_multiple_sources(root_index, root_type, relationship)

          all_errors = relationship_errors + field_params_errors + equivalent_field_errors + has_had_multiple_sources_errors +
            [routing_error, rollover_timestamp_error].compact

          if all_errors.empty?
            update_target = UpdateTargetFactory.new_normal_indexing_update_target(
              type: root_type.name,
              relationship: resolved_chain.qualified_relationship,
              id_source: root_relationship.foreign_key,
              sourced_from_nested_params: SchemaArtifacts::RuntimeMetadata::SourcedFromNestedParams.new(
                field_params: field_params,
                path_identifier_params: resolved_chain.path_identifier_params
              ),
              routing_value_source: routing_value_source,
              rollover_timestamp_value_source: rollover_timestamp_value_source
            )
          end

          [update_target, all_errors]
        end

        private

        # @dynamic object_type, sourced_fields, resolved_chain, field_path_resolver, schema_def_state
        attr_reader :object_type, :sourced_fields, :resolved_chain, :field_path_resolver, :schema_def_state

        # The leaf relationship the chain was resolved from — the one backing this type's `sourced_from` fields.
        def relationship
          resolved_chain.leaf_relationship
        end

        def root_relationship
          resolved_chain.root_relationship
        end

        def root_type
          root_relationship.parent_type
        end

        def root_index
          resolved_chain.root_index
        end

        def related_type
          @related_type ||= schema_def_state.object_types_by_name.fetch(relationship.related_type.unwrap_non_null.name)
        end

        # Applies validations on the relationships backing nested `sourced_from` fields. Only the leaf must be
        # `relates_to_one` (it's where a value is sourced through), but every relationship in the chain joins on
        # a foreign key that routes the source event, so each must be routable (inbound foreign key, no filter).
        def validate_relationships
          leaf_prefix = UpdateTargetResolverSupport.relationship_error_prefix(relationship, sourced_fields)

          UpdateTargetResolverSupport.validate_relationship_cardinality(relationship, error_prefix: leaf_prefix) +
            resolved_chain.relationships.flat_map do |chain_relationship|
              error_prefix = UpdateTargetResolverSupport.relationship_error_prefix(chain_relationship, sourced_fields)
              UpdateTargetResolverSupport.validate_relationship_routability(chain_relationship, error_prefix: error_prefix)
            end
        end

        # Resolves a routing/rollover field source via the shared helper, supplying the root type, index, and
        # relationship — the update target updates the root indexed type via the root relationship, so routing
        # and rollover (and the `equivalent_field` config) are resolved there.
        def resolve_field_source(adapter)
          UpdateTargetResolverSupport.resolve_field_source(
            adapter,
            relationship: root_relationship,
            index_def: root_index,
            related_type: related_type,
            field_path_resolver: field_path_resolver,
            updated_type: root_type
          )
        end
      end
    end
  end
end
