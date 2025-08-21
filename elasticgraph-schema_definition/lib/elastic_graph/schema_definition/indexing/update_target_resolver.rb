# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/params"
require "elastic_graph/schema_definition/indexing/update_target_factory"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Responsible for resolving a relationship and a set of `sourced_from` fields into an `UpdateTarget`
      # that contains the instructions for how the primary type should be updated from the related type's
      # source events.
      #
      # @private
      class UpdateTargetResolver
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
          data_params, data_params_errors = resolve_data_params
          routing_value_source, routing_error = resolve_field_source(RoutingSourceAdapter)
          rollover_timestamp_value_source, rollover_timestamp_error = resolve_field_source(RolloverTimestampSourceAdapter)
          equivalent_field_errors = resolved_relationship.relationship.validate_equivalent_fields(field_path_resolver)

          all_errors = relationship_errors + data_params_errors + equivalent_field_errors + [routing_error, rollover_timestamp_error].compact

          if all_errors.empty?
            update_target = UpdateTargetFactory.new_normal_indexing_update_target(
              type: object_type.name,
              relationship: resolved_relationship.relationship_name,
              id_source: resolved_relationship.relation_metadata.foreign_key,
              data_params: data_params,
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
          errors = [] # : ::Array[::String]

          if resolved_relationship.relationship.many?
            errors << "#{relationship_error_prefix} is a `relates_to_many` relationship, but `sourced_from` is only supported on a `relates_to_one` relationship."
          end

          relation_metadata = resolved_relationship.relationship_field.runtime_metadata_graphql_field.relation # : SchemaArtifacts::RuntimeMetadata::Relation
          if relation_metadata.direction == :out
            errors << "#{relationship_error_prefix} has an outbound foreign key (`dir: :out`), but `sourced_from` is only supported via inbound foreign key (`dir: :in`) relationships."
          end

          unless relation_metadata.additional_filter.empty?
            errors << "#{relationship_error_prefix} is a `relationship` using an `additional_filter` but `sourced_from` is not supported on relationships with `additional_filter`."
          end

          errors
        end

        # Helper method for building the prefix of relationship-related error messages.
        def relationship_error_prefix
          sourced_fields_description = "(referenced from `sourced_from` on field(s): #{sourced_fields.map { |f| "`#{f.name}`" }.join(", ")})"
          "`#{object_type.name}.#{resolved_relationship.relationship_name}` #{sourced_fields_description}"
        end

        # Resolves the `sourced_fields` into a data params map, validating them along the way.
        #
        # Returns a tuple of the data params and a list of any errors that occurred during resolution.
        def resolve_data_params
          related_type = resolved_relationship.related_type
          errors = [] # : ::Array[::String]

          data_params = sourced_fields.filter_map do |field|
            field_source = field.source # : SchemaElements::FieldSource

            referenced_field_path = field_path_resolver.resolve_public_path(related_type, field_source.field_path) do |parent_field|
              !parent_field.type.list?
            end

            if referenced_field_path.nil?
              explanation =
                if field_source.field_path.include?(".")
                  "could not be resolved: some parts do not exist on their respective types as non-list fields"
                else
                  "does not exist as an indexing field"
                end

              errors << "`#{object_type.name}.#{field.name}` has an invalid `sourced_from` argument: `#{related_type.name}.#{field_source.field_path}` #{explanation}."
              nil
            elsif referenced_field_path.type.unwrap_non_null != field.type.unwrap_non_null
              errors << "The type of `#{object_type.name}.#{field.name}` is `#{field.type}`, but the type of it's source (`#{related_type.name}.#{field_source.field_path}`) is `#{referenced_field_path.type}`. These must agree to use `sourced_from`."
              nil
            elsif field.type.non_null?
              errors << "The type of `#{object_type.name}.#{field.name}` (`#{field.type}`) is not nullable, but this is not allowed for `sourced_from` fields since the value will be `null` before the related type's event is ingested."
              nil
            else
              param = SchemaArtifacts::RuntimeMetadata::DynamicParam.new(
                source_path: referenced_field_path.path_in_index,
                cardinality: :one
              )

              [field.name_in_index, param]
            end
          end.to_h

          [data_params, errors]
        end

        # Helper method that assists with resolving `routing_value_source` and `rollover_timestamp_value_source`.
        # Uses an `adapter` for the differences in these two cases.
        #
        # Returns a tuple of the resolved source (if successful) and an error (if invalid).
        def resolve_field_source(adapter)
          index_def = object_type.index_def # : Index

          field_source_graphql_path_string = adapter.get_field_source(resolved_relationship.relationship, index_def) do |local_need|
            relationship_name = resolved_relationship.relationship_name

            error = "Cannot update `#{object_type.name}` documents with data from related `#{relationship_name}` events, " \
              "because #{adapter.cannot_update_reason(object_type, relationship_name)}. To fix it, add a call like this to the " \
              "`#{object_type.name}.#{relationship_name}` relationship definition: `rel.equivalent_field " \
              "\"[#{resolved_relationship.related_type.name} field]\", locally_named: \"#{local_need}\"`."

            return [nil, error]
          end

          if field_source_graphql_path_string
            field_path = field_path_resolver.resolve_public_path(resolved_relationship.related_type, field_source_graphql_path_string) do |parent_field|
              !parent_field.type.list?
            end

            [field_path&.path_in_index, nil]
          else
            [nil, nil]
          end
        end

        # Adapter for the `routing_value_source` case for use by `resolve_field_source`.
        #
        # @private
        module RoutingSourceAdapter
          def self.get_field_source(relationship, index, &block)
            relationship.routing_value_source_for_index(index, &block)
          end

          def self.cannot_update_reason(object_type, relationship_name)
            "`#{object_type.name}` uses custom shard routing but we don't know what `#{relationship_name}` field to use " \
            "to route the `#{object_type.name}` update requests"
          end
        end

        # Adapter for the `rollover_timestamp_value_source` case for use by `resolve_field_source`.
        #
        # @private
        module RolloverTimestampSourceAdapter
          def self.get_field_source(relationship, index, &block)
            relationship.rollover_timestamp_value_source_for_index(index, &block)
          end

          def self.cannot_update_reason(object_type, relationship_name)
            "`#{object_type.name}` uses a rollover index but we don't know what `#{relationship_name}` timestamp field to use " \
            "to select an index for the `#{object_type.name}` update requests"
          end
        end
      end
    end
  end
end
