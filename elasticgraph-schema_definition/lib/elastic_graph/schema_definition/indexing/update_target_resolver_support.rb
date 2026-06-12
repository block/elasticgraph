# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/params"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Shared logic used by both `TopLevelUpdateTargetResolver` (top-level `sourced_from`) and
      # `NestedUpdateTargetResolver` (nested `sourced_from`) to build their `UpdateTarget`s. The two resolvers
      # differ in *which* type, relationship, and index they operate on, but resolve `sourced_from` fields,
      # routing, and rollover the same way—so that common logic lives here.
      #
      # @private
      module UpdateTargetResolverSupport
        # Resolves `sourced_fields` into a `[field_name_in_index => DynamicParam]` map, validating each field
        # against its source on `related_type`. Returns a tuple of the params map and a list of any errors.
        def self.resolve_sourced_field_params(object_type:, related_type:, sourced_fields:, field_path_resolver:)
          errors = [] # : ::Array[::String]

          field_params = sourced_fields.filter_map do |field|
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
              errors << "The type of `#{object_type.name}.#{field.name}` is `#{field.type}`, but the type of its source (`#{related_type.name}.#{field_source.field_path}`) is `#{referenced_field_path.type}`. These must agree to use `sourced_from`."
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

          [field_params, errors]
        end

        # Resolves the `routing_value_source` or `rollover_timestamp_value_source` for an `UpdateTarget`, using
        # an `adapter` for the differences between the two cases. The value is drawn from `relationship`'s
        # `equivalent_field` configuration and resolved to an indexing path on `related_type`. `index_def` is the
        # index needing the value, and `updated_type` is the indexed type being updated (used in error messages).
        #
        # Returns a tuple of the resolved source (if successful) and an error (if invalid).
        def self.resolve_field_source(adapter, relationship:, index_def:, related_type:, field_path_resolver:, updated_type:)
          field_source_graphql_path_string = adapter.get_field_source(relationship, index_def) do |local_need|
            error = "Cannot update `#{updated_type.name}` documents with data from related `#{relationship.name}` events, " \
              "because #{adapter.cannot_update_reason(updated_type, relationship.name)}. To fix it, add a call like this to the " \
              "`#{updated_type.name}.#{relationship.name}` relationship definition: `rel.equivalent_field " \
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

        # Validates that `relationship` is `relates_to_one`, since a `sourced_from` field copies a value from a
        # single source record and a `relates_to_many` relationship has no single value to copy. `error_prefix`
        # identifies the offending relationship (and the `sourced_from` fields that depend on it) in the message.
        #
        # Returns a list of any errors found.
        def self.validate_relationship_cardinality(relationship, error_prefix:)
          return [] unless relationship.many?

          ["#{error_prefix} is a `relates_to_many` relationship, but `sourced_from` is only supported on a " \
            "`relates_to_one` relationship."]
        end

        # Validates that `relationship` can route `sourced_from` source events to the documents they update: it
        # must use an inbound foreign key (so the event carries the key) and no `additional_filter` (which the
        # `sourced_from` update path ignores, so a filtered relationship would silently mismatch). `error_prefix`
        # identifies the offending relationship (and the `sourced_from` fields that depend on it) in the messages.
        #
        # Returns a list of any errors found.
        def self.validate_relationship_routability(relationship, error_prefix:)
          errors = [] # : ::Array[::String]
          relation_metadata = relationship.runtime_metadata # : SchemaArtifacts::RuntimeMetadata::Relation

          if relation_metadata.direction == :out
            errors << "#{error_prefix} has an outbound foreign key (`dir: :out`), but `sourced_from` is only " \
              "supported via inbound foreign key (`dir: :in`) relationships."
          end

          unless relation_metadata.additional_filter.empty?
            errors << "#{error_prefix} uses an `additional_filter`, but `sourced_from` is not supported on " \
              "relationships with `additional_filter`."
          end

          errors
        end

        # Builds the prefix of a relationship-related `sourced_from` error: the `Type.relationship` description,
        # followed by the `sourced_from` fields that depend on it (so the author knows what's affected). Only
        # called when there are `sourced_fields` (a relationship with none produces no update target to validate).
        def self.relationship_error_prefix(relationship, sourced_fields)
          fields_description = sourced_fields.map { |f| "`#{f.name}`" }.join(", ")
          "`#{relationship.parent_type.name}.#{relationship.name}` (referenced from `sourced_from` on field(s): #{fields_description})"
        end

        # Validates that `index` (which `type` writes to, sourcing data via `relationship`) has been configured
        # with `has_had_multiple_sources!`. `sourced_from` makes an index multi-sourced, and ElasticGraph needs
        # that flag to filter incomplete documents correctly.
        #
        # Returns a list of any errors found.
        def self.validate_has_had_multiple_sources(index, type, relationship)
          return [] if index.has_had_multiple_sources_flag

          ["Type `#{type.name}` has `sourced_from` fields (via `#{relationship.parent_type.name}.#{relationship.name}`) but " \
            "its index `#{index.name}` has not been configured with `has_had_multiple_sources!`. To resolve this, add " \
            "`i.has_had_multiple_sources!` within the `t.index \"#{index.name}\"` block. This flag is required because " \
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

          def self.cannot_update_reason(updated_type, relationship_name)
            "`#{updated_type.name}` uses custom shard routing but we don't know what `#{relationship_name}` field to use " \
            "to route the `#{updated_type.name}` update requests"
          end
        end

        # Adapter for the `rollover_timestamp_value_source` case for use by `resolve_field_source`.
        #
        # @private
        module RolloverTimestampSourceAdapter
          def self.get_field_source(relationship, index, &block)
            relationship.rollover_timestamp_value_source_for_index(index, &block)
          end

          def self.cannot_update_reason(updated_type, relationship_name)
            "`#{updated_type.name}` uses a rollover index but we don't know what `#{relationship_name}` timestamp field to use " \
            "to select an index for the `#{updated_type.name}` update requests"
          end
        end
      end
    end
  end
end
