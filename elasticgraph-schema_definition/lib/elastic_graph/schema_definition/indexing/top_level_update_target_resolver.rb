# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/params"
require "elastic_graph/schema_definition/indexing/update_target_factory"
require "elastic_graph/schema_definition/indexing/update_target_resolver_support"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Resolves a relationship and a set of `sourced_from` fields into an `UpdateTarget` that instructs the
      # indexer how to update a type from the related type's source events. This handles the *top-level* case,
      # where the `sourced_from` fields live directly on an indexed type and the target updates that same
      # indexed type. (The *nested* case—`sourced_from` fields on a type embedded within an indexed type—is
      # handled by `NestedUpdateTargetResolver`.)
      #
      # @private
      class TopLevelUpdateTargetResolver
        def initialize(
          object_type:,
          resolved_relationship:,
          sourced_fields:,
          field_path_resolver:
        )
          @object_type = object_type
          @resolved_relationship = resolved_relationship
          @sourced_fields = sourced_fields
          @field_path_resolver = field_path_resolver
        end

        # Resolves the `object_type`, `resolved_relationship`, and `sourced_fields` into an `UpdateTarget`, validating
        # that everything is defined correctly.
        #
        # Returns a tuple of the `update_target` (if valid), and a list of errors.
        def resolve
          relationship_errors = validate_relationship
          top_level_fields_params, top_level_fields_params_errors = UpdateTargetResolverSupport.resolve_sourced_field_params(
            object_type: object_type,
            related_type: related_type,
            sourced_fields: sourced_fields,
            field_path_resolver: field_path_resolver
          )
          routing_value_source, routing_error = resolve_field_source(UpdateTargetResolverSupport::RoutingSourceAdapter)
          rollover_timestamp_value_source, rollover_timestamp_error = resolve_field_source(UpdateTargetResolverSupport::RolloverTimestampSourceAdapter)
          equivalent_field_errors = resolved_relationship.relationship.validate_equivalent_fields(field_path_resolver)
          index_def = object_type.own_index_def # : Index
          has_had_multiple_sources_errors = UpdateTargetResolverSupport.validate_has_had_multiple_sources(
            index_def, object_type, resolved_relationship.relationship
          )

          all_errors = relationship_errors + top_level_fields_params_errors + equivalent_field_errors +
            has_had_multiple_sources_errors + [routing_error, rollover_timestamp_error].compact

          if all_errors.empty?
            update_target = UpdateTargetFactory.new_normal_indexing_update_target(
              type: object_type.name,
              relationship: resolved_relationship.relationship_name,
              id_source: resolved_relationship.relation_metadata.foreign_key,
              top_level_fields_params: top_level_fields_params,
              routing_value_source: routing_value_source,
              rollover_timestamp_value_source: rollover_timestamp_value_source
            )
          end

          [update_target, all_errors]
        end

        private

        # @dynamic object_type, resolved_relationship, sourced_fields, field_path_resolver
        attr_reader :object_type, :resolved_relationship, :sourced_fields, :field_path_resolver

        # Applies additional validations (beyond what `RelationshipResolver` applies) on relationships that are
        # used by `sourced_from` fields.
        def validate_relationship
          relationship = resolved_relationship.relationship
          error_prefix = UpdateTargetResolverSupport.relationship_error_prefix(relationship, sourced_fields)

          UpdateTargetResolverSupport.validate_relationship_cardinality(relationship, error_prefix: error_prefix) +
            UpdateTargetResolverSupport.validate_relationship_routability(relationship, error_prefix: error_prefix)
        end

        # The related type whose source events feed this update target — where `sourced_from` fields are resolved.
        def related_type
          resolved_relationship.related_type
        end

        # Resolves a routing/rollover field source via the shared helper, supplying the top-level type, index,
        # and relationship.
        def resolve_field_source(adapter)
          index_def = object_type.own_index_def # : Index

          UpdateTargetResolverSupport.resolve_field_source(
            adapter,
            relationship: resolved_relationship.relationship,
            index_def: index_def,
            related_type: related_type,
            field_path_resolver: field_path_resolver,
            updated_type: object_type
          )
        end
      end
    end
  end
end
