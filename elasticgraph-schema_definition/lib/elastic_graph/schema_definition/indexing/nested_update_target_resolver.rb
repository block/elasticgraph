# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/nested_sourced_path_segment"
require "elastic_graph/schema_artifacts/runtime_metadata/params"
require "elastic_graph/schema_definition/indexing/update_target_factory"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Responsible for resolving a nested relationship chain and a set of `sourced_from` fields
      # into an `UpdateTarget` for updating nested elements within a root indexed type.
      #
      # @private
      class NestedUpdateTargetResolver
        def initialize(
          object_type:,
          relationship:,
          sourced_fields:,
          resolved_chain:,
          field_path_resolver:,
          schema_def_state:
        )
          @object_type = object_type
          @relationship = relationship
          @sourced_fields = sourced_fields
          @resolved_chain = resolved_chain
          @field_path_resolver = field_path_resolver
          @schema_def_state = schema_def_state
        end

        # Returns a tuple of [update_target, errors].
        # If errors is non-empty, update_target will be nil.
        def resolve
          errors = [] # : ::Array[::String]

          if relationship.many?
            errors << "`#{object_type.name}.#{relationship.name}` is a `relates_to_many` relationship, " \
              "but nested `sourced_from` is only supported on a `relates_to_one` relationship."
            return [nil, errors]
          end

          field_params = resolve_nested_sourced_data_params(errors)
          return [nil, errors] if field_params.empty? && errors.any?

          path_identifier_params = build_path_identifier_params
          nested_sourced_paths = build_nested_sourced_paths
          routing_value_source = resolve_routing(errors)
          rollover_timestamp_value_source = resolve_rollover(errors)
          validate_has_had_multiple_sources(errors)

          if errors.any?
            [nil, errors]
          else
            # Register the path config on the destination index so it's available at runtime.
            resolved_chain.root_indexed_type.index_def.register_nested_sourced_paths(relationship.name, nested_sourced_paths)

            nested_sourced_data_params = SchemaArtifacts::RuntimeMetadata::NestedSourcedDataParams.new(
              field_params: field_params,
              path_identifier_params: path_identifier_params
            )

            update_target = UpdateTargetFactory.new_normal_indexing_update_target(
              type: resolved_chain.root_indexed_type.name,
              relationship: relationship.name,
              id_source: resolved_chain.root_relationship.foreign_key,
              top_level_fields_params: {},
              nested_sourced_data_params: nested_sourced_data_params,
              routing_value_source: routing_value_source,
              rollover_timestamp_value_source: rollover_timestamp_value_source
            )

            [update_target, errors]
          end
        end

        private

        # @dynamic object_type, relationship, sourced_fields, resolved_chain, field_path_resolver, schema_def_state
        attr_reader :object_type, :relationship, :sourced_fields, :resolved_chain, :field_path_resolver, :schema_def_state

        def related_type
          @related_type ||= schema_def_state.object_types_by_name[relationship.related_type.unwrap_non_null.name]
        end

        def resolve_nested_sourced_data_params(errors)
          sourced_fields.filter_map do |field|
            field_source = field.source # : SchemaElements::FieldSource
            referenced_field_path = field_path_resolver.resolve_public_path(related_type, field_source.field_path) do |parent_field|
              !parent_field.type.list?
            end

            if referenced_field_path.nil?
              errors << "`#{object_type.name}.#{field.name}` has an invalid `sourced_from` argument: " \
                "`#{related_type.name}.#{field_source.field_path}` does not exist as an indexing field."
              nil
            else
              param = SchemaArtifacts::RuntimeMetadata::DynamicParam.new(
                source_path: referenced_field_path.path_in_index,
                cardinality: :one
              )
              [field.name_in_index, param]
            end
          end.to_h
        end

        def build_path_identifier_params
          resolved_chain.path_segments.filter_map do |segment|
            # Only list segments need identifier fields — object segments have no ambiguity.
            next unless segment.embedding_field.type.list?

            source_field = segment.source_field
            [source_field, SchemaArtifacts::RuntimeMetadata::DynamicParam.new(
              source_path: source_field,
              cardinality: :one
            )]
          end.to_h
        end

        def build_nested_sourced_paths
          resolved_chain.path_segments.map do |segment|
            if segment.embedding_field.type.list?
              SchemaArtifacts::RuntimeMetadata::ListPathSegment.new(
                field: segment.embedding_field.name_in_index,
                match_field: segment.match_field,
                source_field: segment.source_field
              )
            else
              SchemaArtifacts::RuntimeMetadata::ObjectPathSegment.new(
                field: segment.embedding_field.name_in_index
              )
            end
          end
        end

        def resolve_routing(errors)
          root_rel = resolved_chain.root_relationship
          root_index = resolved_chain.root_indexed_type.index_def

          routing_value_source = root_rel.routing_value_source_for_index(root_index) do |local_need|
            errors << "Cannot update `#{resolved_chain.root_indexed_type.name}` documents with nested sourced data from " \
              "`#{relationship.name}` events, because `#{resolved_chain.root_indexed_type.name}` uses custom shard routing " \
              "but we don't know what field to use to route the update requests. To fix it, add a call like this to the " \
              "`#{resolved_chain.root_indexed_type.name}.#{root_rel.name}` relationship definition: " \
              "`rel.equivalent_field \"[#{related_type.name} field]\", locally_named: \"#{local_need}\"`."
            return [nil, errors]
          end

          if routing_value_source
            field_path = field_path_resolver.resolve_public_path(related_type, routing_value_source) do |parent_field|
              !parent_field.type.list?
            end
            field_path&.path_in_index
          end
        end

        def resolve_rollover(errors)
          root_rel = resolved_chain.root_relationship
          root_index = resolved_chain.root_indexed_type.index_def

          rollover_value_source = root_rel.rollover_timestamp_value_source_for_index(root_index) do |local_need|
            errors << "Cannot update `#{resolved_chain.root_indexed_type.name}` documents with nested sourced data from " \
              "`#{relationship.name}` events, because `#{resolved_chain.root_indexed_type.name}` uses a rollover index " \
              "but we don't know what field to use to select an index for the update requests. To fix it, add a call like this to the " \
              "`#{resolved_chain.root_indexed_type.name}.#{root_rel.name}` relationship definition: " \
              "`rel.equivalent_field \"[#{related_type.name} field]\", locally_named: \"#{local_need}\"`."
            return [nil, errors]
          end

          if rollover_value_source
            field_path = field_path_resolver.resolve_public_path(related_type, rollover_value_source) do |parent_field|
              !parent_field.type.list?
            end
            field_path&.path_in_index
          end
        end

        def validate_has_had_multiple_sources(errors)
          root_type = resolved_chain.root_indexed_type
          root_index_def = root_type.index_def
          if root_index_def && !root_index_def.has_had_multiple_sources_flag
            errors << "Type `#{root_type.name}` has nested `sourced_from` fields (via `#{object_type.name}.#{relationship.name}`) " \
              "but its index `#{root_index_def.name}` has not been configured with `has_had_multiple_sources!`. " \
              "To resolve this, add `i.has_had_multiple_sources!` within the `t.index \"#{root_index_def.name}\"` block."
          end
        end
      end
    end
  end
end
