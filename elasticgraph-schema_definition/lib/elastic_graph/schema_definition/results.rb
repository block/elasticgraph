# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/runtime_metadata/schema"
require "elastic_graph/schema_artifacts/artifacts_helper_methods"
require "elastic_graph/schema_definition/indexing/event_envelope"
require "elastic_graph/schema_definition/indexing/json_schema_with_metadata"
require "elastic_graph/schema_definition/indexing/relationship_resolver"
require "elastic_graph/schema_definition/indexing/update_target_resolver"
require "elastic_graph/schema_definition/mixins/has_readable_to_s_and_inspect"
require "elastic_graph/schema_definition/schema_elements/field_path"
require "elastic_graph/schema_definition/scripting/file_system_repository"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  module SchemaDefinition
    # Provides the results of defining a schema.
    #
    # @note This class is designed to implement the same interface as `ElasticGraph::SchemaArtifacts::FromDisk`, so that it can be used
    # interchangeably with schema artifacts loaded from disk. This allows the artifacts to be used in tests without having to dump them or
    # reload them.
    class Results < Support::MemoizableData.define(:state)
      include Mixins::HasReadableToSAndInspect.new
      include SchemaArtifacts::ArtifactsHelperMethods

      # @return [String] the generated GraphQL SDL schema string dumped as `schema.graphql`
      def graphql_schema_string
        @graphql_schema_string ||= generate_sdl
      end

      # @return [Hash<String, Object>] the Elasticsearch/OpenSearch configuration dumped as `datastore_config.yaml`
      def datastore_config
        @datastore_config ||= generate_datastore_config
      end

      # @return [Hash<String, Object>] runtime metadata used by other parts of ElasticGraph and dumped as `runtime_metadata.yaml`
      def runtime_metadata
        @runtime_metadata ||= build_runtime_metadata
      end

      # @param version [Integer] desired JSON schema version
      # @return [Hash<String, Object>] the JSON schema for the requested version, if available
      # @raise [Errors::NotFoundError] if the requested JSON schema version is not available
      def json_schemas_for(version)
        unless available_json_schema_versions.include?(version)
          raise Errors::NotFoundError, "The requested json schema version (#{version}) is not available. Available versions: #{available_json_schema_versions.to_a.join(", ")}."
        end

        @latest_versioned_json_schema ||= merge_field_metadata_into_json_schema(current_public_json_schema).json_schema
      end

      # @return [Set<Integer>] set of available JSON schema versions
      def available_json_schema_versions
        @available_json_schema_versions ||= Set[latest_json_schema_version]
      end

      # @return [Hash<String, Object>] the newly generated JSON schema
      def latest_json_schema_version
        current_public_json_schema[JSON_SCHEMA_VERSION_KEY]
      end

      # @private
      def json_schema_version_setter_location
        state.json_schema_version_setter_location
      end

      # @private
      def json_schema_field_metadata_by_type_and_field_name
        @json_schema_field_metadata_by_type_and_field_name ||= json_schema_indexing_field_types_by_name
          .transform_values(&:json_schema_field_metadata_by_field_name)
      end

      # @private
      def current_public_json_schema
        @current_public_json_schema ||= build_public_json_schema
      end

      # @private
      def merge_field_metadata_into_json_schema(json_schema)
        json_schema_with_metadata_merger.merge_metadata_into(json_schema)
      end

      # @private
      def unused_deprecated_elements
        json_schema_with_metadata_merger.unused_deprecated_elements
      end

      # @private
      STATIC_SCRIPT_REPO = Scripting::FileSystemRepository.new(::File.join(__dir__.to_s, "scripting", "scripts"))

      # @private
      def derived_indexing_type_names
        @derived_indexing_type_names ||= state
          .object_types_by_name
          .values
          .flat_map { |type| type.derived_indexed_types.map { |dit| dit.destination_type_ref.name } }
          .to_set
      end

      private

      def after_initialize
        # Record that we are now generating results so that caching can kick in.
        state.user_definition_complete = true
      end

      def json_schema_with_metadata_merger
        @json_schema_with_metadata_merger ||= Indexing::JSONSchemaWithMetadata::Merger.new(self)
      end

      def generate_datastore_config
        # We need to check this before generating our datastore configuration.
        # We can't generate a mapping from a recursively defined schema type.
        check_for_circular_dependencies!

        index_templates, indices = state.object_types_by_name.values
          .flat_map(&:indices)
          .sort_by(&:name)
          .partition(&:rollover_config)

        datastore_scripts = (build_dynamic_scripts + STATIC_SCRIPT_REPO.scripts)

        {
          "index_templates" => index_templates.to_h { |i| [i.name, i.to_index_template_config] },
          "indices" => indices.to_h { |i| [i.name, i.to_index_config] },
          "scripts" => datastore_scripts.to_h { |s| [s.id, s.to_artifact_payload] }
        }
      end

      def build_dynamic_scripts
        state.object_types_by_name.values
          .flat_map(&:derived_indexed_types)
          .map(&:painless_script)
      end

      def build_runtime_metadata
        extra_update_targets_by_object_type_name = identify_extra_update_targets_by_object_type_name

        object_types_by_name = all_types_except_root_query_type
          .select { |t| t.respond_to?(:graphql_fields_by_name) }
          .to_h { |type| [type.name, (_ = type).runtime_metadata(extra_update_targets_by_object_type_name.fetch(type.name) { [] })] }

        scalar_types_by_name = state.scalar_types_by_name.transform_values(&:runtime_metadata)

        enum_generator = state.factory.new_enums_for_indexed_types

        indexed_enum_types_by_name = state.object_types_by_name.values
          .select(&:indexed?)
          .filter_map { |type| enum_generator.sort_order_enum_for(_ = type) }
          .to_h { |enum_type| [(_ = enum_type).name, (_ = enum_type).runtime_metadata] }

        enum_types_by_name = all_types_except_root_query_type
          .grep(SchemaElements::EnumType) # : ::Array[SchemaElements::EnumType]
          .to_h { |t| [t.name, t.runtime_metadata] }
          .merge(indexed_enum_types_by_name)

        index_definitions_by_name = state.object_types_by_name.values.flat_map(&:indices).to_h do |index|
          [index.name, index.runtime_metadata]
        end

        SchemaArtifacts::RuntimeMetadata::Schema.new(
          object_types_by_name: object_types_by_name,
          scalar_types_by_name: scalar_types_by_name,
          enum_types_by_name: enum_types_by_name,
          index_definitions_by_name: index_definitions_by_name,
          schema_element_names: state.schema_elements,
          graphql_extension_modules: state.graphql_extension_modules,
          static_script_ids_by_scoped_name: STATIC_SCRIPT_REPO.script_ids_by_scoped_name
        )
      end

      # Builds a map, keyed by object type name, of extra `update_targets` that have been generated
      # from any fields that use `sourced_from` on other types.
      def identify_extra_update_targets_by_object_type_name
        # The field_path_resolver memoizes some calculations, and we want the same instance to be
        # used by all UpdateTargetBuilders to maximize its effectiveness.
        field_path_resolver = SchemaElements::FieldPath::Resolver.new
        sourced_field_errors = [] # : ::Array[::String]
        relationship_errors = [] # : ::Array[::String]

        state.object_types_by_name.values.each_with_object(::Hash.new { |h, k| h[k] = [] }) do |object_type, accum|
          fields_with_sources_by_relationship_name =
            if object_type.indices.empty?
              # only indexed types can have `sourced_from` fields, and resolving `fields_with_sources` on an unindexed union type
              # such as `_Entity` when we are using apollo can lead to exceptions when multiple entity types have the same field name
              # that use different mapping types.
              {} # : ::Hash[::String, ::Array[SchemaElements::Field]]
            else
              object_type
                .fields_with_sources
                .group_by { |f| (_ = f.source).relationship_name }
            end

          defined_relationships = object_type
            .graphql_fields_by_name.values
            .select(&:relationship)
            .map(&:name)

          (defined_relationships | fields_with_sources_by_relationship_name.keys).each do |relationship_name|
            sourced_fields = fields_with_sources_by_relationship_name.fetch(relationship_name) { [] }
            relationship_resolver = Indexing::RelationshipResolver.new(
              schema_def_state: state,
              object_type: object_type,
              relationship_name: relationship_name,
              sourced_fields: sourced_fields,
              field_path_resolver: field_path_resolver
            )

            resolved_relationship, relationship_error = relationship_resolver.resolve
            relationship_errors << relationship_error if relationship_error

            if object_type.indices.any? && resolved_relationship && sourced_fields.any?
              update_target_resolver = Indexing::UpdateTargetResolver.new(
                object_type: object_type,
                resolved_relationship: resolved_relationship,
                sourced_fields: sourced_fields,
                field_path_resolver: field_path_resolver
              )

              update_target, errors = update_target_resolver.resolve
              accum[resolved_relationship.related_type.name] << update_target if update_target
              sourced_field_errors.concat(errors)
            end
          end
        end.tap do
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

      # Generates the SDL defined by your schema. Intended to be called only once
      # at the very end (after evaluating the "main" template). `Evaluator` calls this
      # automatically at the end.
      def generate_sdl
        check_for_circular_dependencies!
        state.object_types_by_name.values.each(&:verify_graphql_correctness!)

        type_defs = state.factory
          .new_graphql_sdl_enumerator(all_types_except_root_query_type)
          .map { |sdl| strip_trailing_whitespace(sdl) }

        [type_defs + state.sdl_parts].join("\n\n")
      end

      def build_public_json_schema
        json_schema_version = state.json_schema_version
        if json_schema_version.nil?
          raise Errors::SchemaError, "`json_schema_version` must be specified in the schema. To resolve, add `schema.json_schema_version 1` in a schema definition block."
        end

        indexed_type_names = state.object_types_by_name.values
          .select { |type| type.indexed? && !type.abstract? }
          .reject { |type| derived_indexing_type_names.include?(type.name) }
          .map(&:name)

        definitions_by_name = json_schema_indexing_field_types_by_name
          .transform_values(&:to_json_schema)
          .compact

        {
          "$schema" => JSON_META_SCHEMA,
          JSON_SCHEMA_VERSION_KEY => json_schema_version,
          "$defs" => {
            "ElasticGraphEventEnvelope" => Indexing::EventEnvelope.json_schema(indexed_type_names, json_schema_version)
          }.merge(definitions_by_name)
        }
      end

      def json_schema_indexing_field_types_by_name
        @json_schema_indexing_field_types_by_name ||= state
          .types_by_name.values
          .reject do |t|
            derived_indexing_type_names.include?(t.name) ||
              # Skip graphql framework types
              t.graphql_only?
          end
          .sort_by(&:name)
          .to_h { |type| [type.name, type.to_indexing_field_type] }
      end

      def strip_trailing_whitespace(string)
        string.gsub(/ +$/, "")
      end

      def check_for_circular_dependencies!
        return if @no_circular_dependencies

        referenced_types_by_source_type = state.types_by_name
          .reject { |_, type| type.graphql_only? }
          .each_with_object(::Hash.new { |h, k| h[k] = ::Set.new }) do |(type_name, _), cache|
            recursively_add_referenced_types_to(state.type_ref(type_name), cache)
          end

        circular_reference_sets = referenced_types_by_source_type
          .select { |source_type, referenced_types| referenced_types.include?(source_type) }
          .values
          .uniq

        if circular_reference_sets.any?
          descriptions = circular_reference_sets.map do |set|
            "- The set of #{set.to_a} forms a circular reference chain."
          end

          raise Errors::SchemaError, "Your schema has self-referential types, which are not allowed, since " \
            "it prevents the datastore mapping and GraphQL schema generation from terminating:\n" \
            "#{descriptions.join("\n")}"
        end

        @no_circular_dependencies = true
      end

      def recursively_add_referenced_types_to(source_type_ref, references_cache)
        return unless (source_type = source_type_ref.as_object_type)
        references_set = references_cache[source_type_ref.name] # : ::Set[::String]

        # Recursive references are allowed only when its a relation, so skip that case.
        source_type.graphql_fields_by_name.values.reject { |f| f.relationship }.each do |field|
          field_type = field.type.fully_unwrapped

          if field_type.object? && references_set.add?(field_type.name)
            recursively_add_referenced_types_to(field_type, references_cache)
          end

          field_type_references_set = references_cache[field_type.name] # : ::Set[::String]
          references_set.merge(field_type_references_set)
        end
      end

      def all_types_except_root_query_type
        @all_types_except_root_query_type ||= state.types_by_name.values.flat_map do |registered_type|
          related_types = [registered_type] + registered_type.derived_graphql_types
          apply_customizations_to(related_types, registered_type)
          related_types
        end
      end

      def apply_customizations_to(types, registered_type)
        built_in_customizers = state.built_in_types_customization_blocks
        if built_in_customizers.any? && state.initially_registered_built_in_types.include?(registered_type.name)
          types.each do |type|
            built_in_customizers.each do |customization_block|
              customization_block.call(type)
            end
          end
        end

        unless (unknown_type_names = registered_type.derived_type_customizations_by_name.keys - types.map(&:name)).empty?
          raise Errors::SchemaError,
            "`customize_derived_types` was called on `#{registered_type.name}` with some unrecognized type names " \
             "(#{unknown_type_names.join(", ")}). Maybe some of the derived GraphQL types are misspelled?"
        end

        unless (unknown_type_names = registered_type.derived_field_customizations_by_type_and_field_name.keys - types.map(&:name)).empty?
          raise Errors::SchemaError,
            "`customize_derived_type_fields` was called on `#{registered_type.name}` with some unrecognized type names " \
             "(#{unknown_type_names.join(", ")}). Maybe some of the derived GraphQL types are misspelled?"
        end

        unknown_field_names = (types - [registered_type]).flat_map do |type|
          registered_type.derived_type_customizations_for_type(type).each { |b| b.call(type) }
          field_customizations_by_name = registered_type.derived_field_customizations_by_name_for_type(type)

          if field_customizations_by_name.any? && !type.respond_to?(:graphql_fields_by_name)
            raise Errors::SchemaError,
              "`customize_derived_type_fields` was called on `#{registered_type.name}` with a type that can " \
              "never have fields: `#{type.name}`."
          end

          field_customizations_by_name.filter_map do |field_name, customization_blocks|
            if (field = (_ = type).graphql_fields_by_name[field_name])
              customization_blocks.each { |b| b.call(field) }
              nil
            else
              "#{type.name}.#{field_name}"
            end
          end
        end

        unless unknown_field_names.empty?
          raise Errors::SchemaError,
            "`customize_derived_type_fields` was called on `#{registered_type.name}` with some unrecognized field names " \
            "(#{unknown_field_names.join(", ")}). Maybe one of the field names was misspelled?"
        end
      end
    end
  end
end
