# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/schema_definition/factory"
require "elastic_graph/schema_definition/mixins/has_readable_to_s_and_inspect"
require "elastic_graph/schema_definition/schema_elements/enum_value_namer"
require "elastic_graph/schema_definition/schema_elements/field_path"
require "elastic_graph/schema_definition/schema_elements/type_namer"
require "elastic_graph/schema_definition/schema_elements/sub_aggregation_path"

module ElasticGraph
  module SchemaDefinition
    # Encapsulates all state that needs to be managed while a schema is defined.
    # This is separated from `API` to make it easy to expose some state management
    # helper methods to our internal code without needing to expose it as part of
    # the public API.
    #
    # @private
    class State < Struct.new(
      :api,
      :schema_elements,
      :index_document_sizes,
      :types_by_name,
      :object_types_by_name,
      :scalar_types_by_name,
      :enum_types_by_name,
      :implementations_by_interface_ref,
      :sdl_parts,
      :paginated_collection_element_types,
      :user_defined_fields,
      :renamed_types_by_old_name,
      :deleted_types_by_old_name,
      :renamed_fields_by_type_name_and_old_field_name,
      :deleted_fields_by_type_name_and_old_field_name,
      :json_schema_version,
      :json_schema_version_setter_location,
      :graphql_extension_modules,
      :graphql_resolvers_by_name,
      :resolvers_by_name,
      :initially_registered_built_in_types,
      :built_in_types_customization_blocks,
      :user_definition_complete,
      :user_definition_complete_callbacks,
      :sub_aggregation_paths_by_type,
      :type_refs_by_name,
      :output,
      :type_namer,
      :enum_value_namer
    )
      include Mixins::HasReadableToSAndInspect.new

      def self.with(
        api:,
        schema_elements:,
        index_document_sizes:,
        derived_type_name_formats:,
        type_name_overrides:,
        enum_value_overrides_by_type:,
        output: $stdout
      )
        # @type var types_by_name: SchemaElements::typesByNameHash
        types_by_name = {}

        new(
          api: api,
          schema_elements: schema_elements,
          index_document_sizes: index_document_sizes,
          types_by_name: types_by_name,
          object_types_by_name: {},
          scalar_types_by_name: {},
          enum_types_by_name: {},
          implementations_by_interface_ref: ::Hash.new { |h, k| h[k] = ::Set.new },
          sdl_parts: [],
          paginated_collection_element_types: ::Set.new,
          user_defined_fields: ::Set.new,
          renamed_types_by_old_name: {},
          deleted_types_by_old_name: {},
          renamed_fields_by_type_name_and_old_field_name: ::Hash.new { |h, k| h[k] = {} },
          deleted_fields_by_type_name_and_old_field_name: ::Hash.new { |h, k| h[k] = {} },
          json_schema_version_setter_location: nil,
          json_schema_version: nil,
          graphql_extension_modules: [],
          graphql_resolvers_by_name: {},
          initially_registered_built_in_types: ::Set.new,
          built_in_types_customization_blocks: [],
          user_definition_complete: false,
          user_definition_complete_callbacks: [],
          sub_aggregation_paths_by_type: {},
          type_refs_by_name: {},
          type_namer: SchemaElements::TypeNamer.new(
            format_overrides: derived_type_name_formats,
            name_overrides: type_name_overrides
          ),
          enum_value_namer: SchemaElements::EnumValueNamer.new(enum_value_overrides_by_type),
          output: output
        )
      end

      # @dynamic index_document_sizes?
      alias_method :index_document_sizes?, :index_document_sizes

      def type_ref(name)
        # Type references are immutable and can be safely cached. Here we cache them because we've observed
        # it having a noticeable impact on our test suite runtime.
        type_refs_by_name[name] ||= factory.new_type_reference(name)
      end

      def register_object_interface_or_union_type(type)
        register_type(type, object_types_by_name)
      end

      def register_enum_type(type)
        register_type(type, enum_types_by_name)
      end

      def register_scalar_type(type)
        register_type(type, scalar_types_by_name)
      end

      def register_input_type(type)
        register_type(type)
      end

      def register_renamed_type(type_name, from:, defined_at:, defined_via:)
        renamed_types_by_old_name[from] = factory.new_deprecated_element(
          type_name,
          defined_at: defined_at,
          defined_via: defined_via
        )
      end

      def register_deleted_type(type_name, defined_at:, defined_via:)
        deleted_types_by_old_name[type_name] = factory.new_deprecated_element(
          type_name,
          defined_at: defined_at,
          defined_via: defined_via
        )
      end

      def register_renamed_field(type_name, from:, to:, defined_at:, defined_via:)
        renamed_fields_by_old_field_name = renamed_fields_by_type_name_and_old_field_name[type_name] # : ::Hash[::String, SchemaElements::DeprecatedElement]
        renamed_fields_by_old_field_name[from] = factory.new_deprecated_element(
          to,
          defined_at: defined_at,
          defined_via: defined_via
        )
      end

      def register_deleted_field(type_name, field_name, defined_at:, defined_via:)
        deleted_fields_by_old_field_name = deleted_fields_by_type_name_and_old_field_name[type_name] # : ::Hash[::String, SchemaElements::DeprecatedElement]
        deleted_fields_by_old_field_name[field_name] = factory.new_deprecated_element(
          field_name,
          defined_at: defined_at,
          defined_via: defined_via
        )
      end

      # Registers the given `field` as a user-defined field, unless the user definitions are complete.
      def register_user_defined_field(field)
        user_defined_fields << field
      end

      def user_defined_field_references_by_type_name
        @user_defined_field_references_by_type_name ||= begin
          unless user_definition_complete
            raise Errors::SchemaError, "Cannot access `user_defined_field_references_by_type_name` until the schema definition is complete."
          end

          user_defined_fields.group_by { |f| f.type.fully_unwrapped.name }
        end
      end

      def factory
        @factory ||= Factory.new(self)
      end

      def enums_for_indexed_types
        @enums_for_indexed_types ||= factory.new_enums_for_indexed_types
      end

      def sub_aggregation_paths_for(type)
        sub_aggregation_paths_by_type.fetch(type) do
          SchemaElements::SubAggregationPath.paths_for(type, schema_def_state: self).uniq.tap do |paths|
            # Cache our results if the user has finished their schema definition. Otherwise, it's not safe to cache.
            # :nocov: -- we never execute this with `user_definition_complete == false`
            sub_aggregation_paths_by_type[type] = paths if user_definition_complete
            # :nocov:
          end
        end
      end

      def after_user_definition_complete(&block)
        user_definition_complete_callbacks << block
      end

      def field_path_resolver
        @field_path_resolver ||= SchemaElements::FieldPath::Resolver.new(self)
      end

      private

      RESERVED_TYPE_NAMES = [EVENT_ENVELOPE_JSON_SCHEMA_NAME].to_set

      def register_type(type, additional_type_index = nil)
        name = (_ = type).name

        if RESERVED_TYPE_NAMES.include?(name)
          raise Errors::SchemaError, "`#{name}` cannot be used as a schema type because it is a reserved name."
        end

        if types_by_name.key?(name)
          raise Errors::SchemaError, "Duplicate definition for type #{name} detected. Each type can only be defined once."
        end

        additional_type_index[name] = type if additional_type_index
        types_by_name[name] = type
      end
    end
  end
end
