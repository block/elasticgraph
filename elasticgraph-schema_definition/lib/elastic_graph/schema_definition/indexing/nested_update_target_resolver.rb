# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/params"
require "elastic_graph/schema_artifacts/runtime_metadata/sourced_from_nested_params"
require "elastic_graph/schema_definition/indexing/sourced_field_params_resolver"
require "elastic_graph/schema_definition/indexing/update_target_factory"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Responsible for resolving a nested `parent_relationship` chain and a set of `sourced_from`
      # fields into an `UpdateTarget` that instructs the indexer to update a nested element within
      # the root indexed type when a source event arrives. This is the nested analog of
      # `UpdateTargetResolver`, which handles the top-level (non-nested) `sourced_from` case.
      #
      # @private
      class NestedUpdateTargetResolver
        include SourcedFieldParamsResolver

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
          relationship_errors = validate_relationship
          field_params, field_params_errors = resolve_sourced_field_params
          routing_value_source, routing_error = resolve_field_source(RoutingSourceAdapter)
          rollover_timestamp_value_source, rollover_timestamp_error = resolve_field_source(RolloverTimestampSourceAdapter)
          has_had_multiple_sources_errors = validate_has_had_multiple_sources

          all_errors = relationship_errors + field_params_errors + has_had_multiple_sources_errors +
            [routing_error, rollover_timestamp_error].compact

          if all_errors.empty?
            update_target = UpdateTargetFactory.new_normal_indexing_update_target(
              type: root_type.name,
              relationship: resolved_chain.qualified_relationship,
              id_source: root_relationship.foreign_key,
              top_level_fields_params: {},
              sourced_from_nested_params: SchemaArtifacts::RuntimeMetadata::SourcedFromNestedParams.new(
                field_params: field_params,
                path_identifier_params: build_path_identifier_params
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

        # Applies validations specific to relationships backing nested `sourced_from` fields.
        def validate_relationship
          errors = [] # : ::Array[::String]

          if relationship.many?
            errors << "`#{object_type.name}.#{relationship.name}` is a `relates_to_many` relationship, but nested " \
              "`sourced_from` is only supported on a `relates_to_one` relationship."
          end

          errors
        end

        # Builds the params identifying which nested element to update: one entry per list segment in the
        # chain, pulling the matching value from the segment's foreign key on the source event. Object
        # segments have no ambiguity, so they contribute no identifier.
        def build_path_identifier_params
          resolved_chain.path_segments.filter_map do |segment|
            source_field = segment.source_field_name
            next unless source_field

            param = SchemaArtifacts::RuntimeMetadata::DynamicParam.new(
              source_path: source_field,
              cardinality: :one
            )

            [source_field, param]
          end.to_h
        end

        # Resolves `routing_value_source` and `rollover_timestamp_value_source` against the root
        # relationship and root index, using an `adapter` for the differences between the two cases.
        #
        # Returns a tuple of the resolved source (if successful) and an error (if invalid).
        def resolve_field_source(adapter)
          field_source_graphql_path_string = adapter.get_field_source(root_relationship, root_index) do |local_need|
            # The update is triggered by the leaf relationship's source events (`relationship`), but routing and
            # rollover are resolved through — and `equivalent_field` is configured on — the root relationship.
            error = "Cannot update `#{root_type.name}` documents with nested data from related `#{relationship.name}` " \
              "events, because #{adapter.cannot_update_reason(root_type, root_relationship.name)}. To fix it, add a call " \
              "like this to the `#{root_type.name}.#{root_relationship.name}` relationship definition: `rel.equivalent_field " \
              "\"[#{related_type.name} field]\", locally_named: \"#{local_need}\"`."

            return [nil, error]
          end

          if field_source_graphql_path_string
            field_path = field_path_resolver.resolve_public_path(related_type, field_source_graphql_path_string) do |parent_field|
              !parent_field.type.list?
            end

            [field_path&.path_in_index, nil]
          else
            [nil, nil]
          end
        end

        # Validates that `has_had_multiple_sources!` has been configured on the root index, since nested
        # `sourced_from` makes the root index multi-sourced.
        def validate_has_had_multiple_sources
          return [] if root_index.has_had_multiple_sources_flag

          ["Type `#{root_type.name}` has nested `sourced_from` fields (via `#{object_type.name}.#{relationship.name}`) but " \
            "its index `#{root_index.name}` has not been configured with `has_had_multiple_sources!`. To resolve this, add " \
            "`i.has_had_multiple_sources!` within the `t.index \"#{root_index.name}\"` block. This flag is required because " \
            "indices with multiple sources can contain incomplete documents, and ElasticGraph needs to know this to apply " \
            "proper filtering. Once set, this flag should remain even if you later remove all `sourced_from` fields, as the " \
            "index may still contain historical incomplete documents."]
        end

        # Adapter for the `routing_value_source` case for use by `resolve_field_source`.
        #
        # @private
        module RoutingSourceAdapter
          def self.get_field_source(relationship, index, &block)
            relationship.routing_value_source_for_index(index, &block)
          end

          def self.cannot_update_reason(root_type, relationship_name)
            "`#{root_type.name}` uses custom shard routing but we don't know what `#{relationship_name}` field to use " \
            "to route the `#{root_type.name}` update requests"
          end
        end

        # Adapter for the `rollover_timestamp_value_source` case for use by `resolve_field_source`.
        #
        # @private
        module RolloverTimestampSourceAdapter
          def self.get_field_source(relationship, index, &block)
            relationship.rollover_timestamp_value_source_for_index(index, &block)
          end

          def self.cannot_update_reason(root_type, relationship_name)
            "`#{root_type.name}` uses a rollover index but we don't know what `#{relationship_name}` timestamp field to use " \
            "to select an index for the `#{root_type.name}` update requests"
          end
        end
      end
    end
  end
end
