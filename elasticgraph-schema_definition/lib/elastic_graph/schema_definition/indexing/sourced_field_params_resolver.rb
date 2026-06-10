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
      # Shared logic for resolving a set of `sourced_from` fields into the params map that pulls each field's
      # value from its source path on the related type. Used by both `UpdateTargetResolver` (top-level
      # `sourced_from`) and `NestedUpdateTargetResolver` (nested `sourced_from`), which resolve the same way
      # but build different update targets around the result.
      #
      # Hosts must provide `object_type`, `related_type`, `sourced_fields`, and `field_path_resolver`.
      #
      # @private
      module SourcedFieldParamsResolver
        # Resolves `sourced_fields` into a `[field_name_in_index => DynamicParam]` map, validating each field
        # against its source. Returns a tuple of the params map and a list of any errors.
        def resolve_sourced_field_params
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
      end
    end
  end
end
