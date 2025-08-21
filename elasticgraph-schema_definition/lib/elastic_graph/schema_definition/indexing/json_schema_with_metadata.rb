# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Represents the result of merging a JSON schema with metadata. The result includes both
      # the merged JSON schema and a list of `failed_fields` indicating which fields metadata
      # could not be determined for.
      #
      # @private
      class JSONSchemaWithMetadata < ::Data.define(
        # The JSON schema.
        :json_schema,
        # A set of fields (in the form `Type.field`) that were needed but not found.
        :missing_fields,
        # A set of type names that were needed but not found.
        :missing_types,
        # A set of `DeprecatedElement` objects that create conflicting definitions.
        :definition_conflicts,
        # A set of fields that have been deleted but that must be retained (e.g. for custom shard routing or rollover)
        :missing_necessary_fields
      )
        def json_schema_version
          json_schema.fetch(JSON_SCHEMA_VERSION_KEY)
        end

        # Responsible for building `JSONSchemaWithMetadata` instances.
        #
        # @private
        class Merger
          # @dynamic unused_deprecated_elements
          attr_reader :unused_deprecated_elements

          def initialize(schema_def_results)
            @field_metadata_by_type_and_field_name = schema_def_results.json_schema_field_metadata_by_type_and_field_name
            @renamed_types_by_old_name = schema_def_results.state.renamed_types_by_old_name
            @deleted_types_by_old_name = schema_def_results.state.deleted_types_by_old_name
            @renamed_fields_by_type_name_and_old_field_name = schema_def_results.state.renamed_fields_by_type_name_and_old_field_name
            @deleted_fields_by_type_name_and_old_field_name = schema_def_results.state.deleted_fields_by_type_name_and_old_field_name
            @state = schema_def_results.state
            @derived_indexing_type_names = schema_def_results.derived_indexing_type_names

            @unused_deprecated_elements = (
              @renamed_types_by_old_name.values +
              @deleted_types_by_old_name.values +
              @renamed_fields_by_type_name_and_old_field_name.values.flat_map(&:values) +
              @deleted_fields_by_type_name_and_old_field_name.values.flat_map(&:values)
            ).to_set
          end

          def merge_metadata_into(json_schema)
            missing_fields = ::Set.new
            missing_types = ::Set.new
            definition_conflicts = ::Set.new
            old_type_name_by_current_name = {} # : ::Hash[String, String]

            defs = json_schema.fetch("$defs").to_h do |type_name, type_def|
              if type_name != EVENT_ENVELOPE_JSON_SCHEMA_NAME && (properties = type_def["properties"])
                current_type_name = determine_current_type_name(
                  type_name,
                  missing_types: missing_types,
                  definition_conflicts: definition_conflicts
                )

                if current_type_name
                  old_type_name_by_current_name[current_type_name] = type_name
                end

                properties = properties.to_h do |field_name, prop|
                  unless field_name == "__typename"
                    field_metadata = current_type_name&.then do |name|
                      field_metadata_for(
                        name,
                        field_name,
                        missing_fields: missing_fields,
                        definition_conflicts: definition_conflicts
                      )
                    end

                    prop = prop.merge({"ElasticGraph" => field_metadata&.to_dumpable_hash})
                  end

                  [field_name, prop]
                end

                type_def = type_def.merge({"properties" => properties})
              end

              [type_name, type_def]
            end

            json_schema = json_schema.merge("$defs" => defs)

            JSONSchemaWithMetadata.new(
              json_schema: json_schema,
              missing_fields: missing_fields,
              missing_types: missing_types,
              definition_conflicts: definition_conflicts,
              missing_necessary_fields: identify_missing_necessary_fields(json_schema, old_type_name_by_current_name)
            )
          end

          private

          # Given a historical `type_name`, determines (and returns) the current name for that type.
          def determine_current_type_name(type_name, missing_types:, definition_conflicts:)
            exists_currently = @field_metadata_by_type_and_field_name.key?(type_name)
            deleted = @deleted_types_by_old_name[type_name]&.tap { |elem| @unused_deprecated_elements.delete(elem) }
            renamed = @renamed_types_by_old_name[type_name]&.tap { |elem| @unused_deprecated_elements.delete(elem) }

            if [exists_currently, deleted, renamed].count(&:itself) > 1
              definition_conflicts.merge([deleted, renamed].compact)
            end

            return type_name if exists_currently
            return nil if deleted
            return renamed.name if renamed

            missing_types << type_name
            nil
          end

          # Given a historical `type_name` and `field_name` determines (and returns) the field metadata for it.
          def field_metadata_for(type_name, field_name, missing_fields:, definition_conflicts:)
            full_name = "#{type_name}.#{field_name}"

            current_meta = @field_metadata_by_type_and_field_name.dig(type_name, field_name)
            deleted = @deleted_fields_by_type_name_and_old_field_name.dig(type_name, field_name)&.tap do |elem|
              @unused_deprecated_elements.delete(elem)
            end
            renamed = @renamed_fields_by_type_name_and_old_field_name.dig(type_name, field_name)&.tap do |elem|
              @unused_deprecated_elements.delete(elem)
            end

            if [current_meta, deleted, renamed].count(&:itself) > 1
              definition_conflicts.merge([deleted, renamed].compact.map { |elem| elem.with(name: full_name) })
            end

            return current_meta if current_meta
            return nil if deleted
            return @field_metadata_by_type_and_field_name.dig(type_name, renamed.name) if renamed

            missing_fields << full_name
            nil
          end

          def identify_missing_necessary_fields(json_schema, old_type_name_by_current_name)
            json_schema_resolver = JSONSchemaResolver.new(@state, json_schema, old_type_name_by_current_name)
            version = json_schema.fetch(JSON_SCHEMA_VERSION_KEY)

            types_to_check = @state.object_types_by_name.values.select do |type|
              type.indexed? && !@derived_indexing_type_names.include?(type.name)
            end

            types_to_check.filter_map do |object_type|
              if (index_def = object_type.index_def)
                identify_missing_necessary_fields_for_index_def(object_type, index_def, json_schema_resolver, version)
              end
            end.flatten
          end

          def identify_missing_necessary_fields_for_index_def(object_type, index_def, json_schema_resolver, json_schema_version)
            {
              "routing" => index_def.routing_field_path,
              "rollover" => index_def.rollover_config&.timestamp_field_path
            }.compact.filter_map do |field_type, field_path|
              if json_schema_resolver.necessary_path_missing?(field_path)
                # The JSON schema v # {json_schema_version} artifact has no field that maps to the #{field_type} path of `#{field_path.fully_qualified_path_in_index}`.

                MissingNecessaryField.new(
                  field_type: field_type,
                  fully_qualified_path: field_path.fully_qualified_path_in_index
                )
              end
            end
          end

          class JSONSchemaResolver
            def initialize(state, json_schema, old_type_name_by_current_name)
              @state = state
              @old_type_name_by_current_name = old_type_name_by_current_name
              @meta_by_old_type_and_name_in_index = ::Hash.new do |hash, type_name|
                properties = json_schema.fetch("$defs").fetch(type_name).fetch("properties")

                hash[type_name] = properties.filter_map do |name, prop|
                  if (metadata = prop["ElasticGraph"])
                    [metadata.fetch("nameInIndex"), metadata]
                  end
                end.to_h
              end
            end

            # Indicates if the given `field_path` is (1) necessary and (2) missing from the JSON schema, indicating a problem.
            #
            # - Returns `false` is the given `field_path` is present in the JSON schema.
            # - Returns `false` is the parent type of `field_path` has not been retained in this JSON schema version
            #   (in that case, the field path is not necessary).
            # - Otherwise, returns `true` since the field path is both necessary and missing.
            def necessary_path_missing?(field_path)
              parent_type = field_path.first_part.parent_type.name

              field_path.path_parts.any? do |path_part|
                necessary_path_part_missing?(parent_type, path_part.name_in_index) do |meta|
                  parent_type = @state.type_ref(meta.fetch("type")).fully_unwrapped.name
                end
              end
            end

            private

            def necessary_path_part_missing?(parent_type, name_in_index)
              old_type_name = @old_type_name_by_current_name[parent_type]
              return false unless old_type_name

              meta = @meta_by_old_type_and_name_in_index.dig(old_type_name, name_in_index)
              yield meta if meta
              !meta
            end
          end
        end

        MissingNecessaryField = ::Data.define(:field_type, :fully_qualified_path)
      end
    end
  end
end
