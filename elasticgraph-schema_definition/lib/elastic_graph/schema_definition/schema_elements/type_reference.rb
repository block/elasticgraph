# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"
require "elastic_graph/schema_definition/mixins/verifies_graphql_name"
require "elastic_graph/schema_definition/schema_elements/type_namer"
require "elastic_graph/support/memoizable_data"
require "forwardable"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Represents a reference to a type. This is basically just a name of a type,
      # with the ability to resolve it to an actual type object on demand. In addition,
      # we provide some useful logic that is based entirely on the type name.
      #
      # This is necessary because GraphQL does not require that types are defined
      # before they are referenced.  (And also you can have circular type dependencies).
      # Therefore, we need to use a reference to a type initially, and can later resolve
      # it to a concrete type object as needed.
      #
      # @private
      class TypeReference < Support::MemoizableData.define(:name, :schema_def_state)
        extend Forwardable
        # @dynamic type_namer
        def_delegator :schema_def_state, :type_namer

        # Extracts the type without any non-null or list wrappings it has.
        def fully_unwrapped
          schema_def_state.type_ref(unwrapped_name)
        end

        # Removes any non-null wrappings the type has.
        def unwrap_non_null
          schema_def_state.type_ref(name.delete_suffix("!"))
        end

        def wrap_non_null
          return self if non_null?
          schema_def_state.type_ref("#{name}!")
        end

        # Removes the list wrapping if this is a list.
        #
        # If the outer wrapping is non-null, unwraps that as well.
        def unwrap_list
          schema_def_state.type_ref(unwrap_non_null.name.delete_prefix("[").delete_suffix("]"))
        end

        # Returns the `ObjectType`, `UnionType` or `InterfaceType` object to which this
        # type name refers, if it is the name of one of those kinds of types.
        #
        # Ignores any non-null wrapping on the type, if there is one.
        def as_object_type
          type = _ = unwrap_non_null.resolved
          type if type.respond_to?(:graphql_fields_by_name)
        end

        # Returns `true` if this is known to be an object type of some sort (including interface types,
        # union types, and proper object types).
        #
        # Returns `false` if this is known to be a leaf type of some sort (either a scalar or enum).
        # Returns `false` if this is a list type (either a list of objects or leafs).
        #
        # Raises an error if it cannot be determined either from the name or by resolving the type.
        #
        # Ignores any non-null wrapping on the type, if there is one.
        def object?
          return unwrap_non_null.object? if non_null?

          if (resolved_type = resolved)
            return resolved_type.respond_to?(:graphql_fields_by_name)
          end

          # For derived GraphQL types, the name usually implies what kind of type it is.
          # The derived types get generated last, so this prediate may be called before the
          # type has been defined.
          case schema_kind_implied_by_name
          when :object
            true
          when :enum
            false
          else
            # If we can't determine the type from the name, just raise an error.
            raise Errors::SchemaError, "Type `#{name}` cannot be resolved. Is it misspelled?"
          end
        end

        def enum?
          return unwrap_non_null.enum? if non_null?

          if (resolved_type = resolved)
            return resolved_type.is_a?(EnumType)
          end

          # For derived GraphQL types, the name usually implies what kind of type it is.
          # The derived types get generated last, so this prediate may be called before the
          # type has been defined.
          case schema_kind_implied_by_name
          when :object
            false
          when :enum
            true
          else
            # If we can't determine the type from the name, just raise an error.
            raise Errors::SchemaError, "Type `#{name}` cannot be resolved. Is it misspelled?"
          end
        end

        # Returns `true` if this is known to be a scalar type or enum type.
        # Returns `false` if this is known to be an object type or list type of any sort.
        #
        # Raises an error if it cannot be determined either from the name or by resolving the type.
        #
        # Ignores any non-null wrapping on the type, if there is one.
        def leaf?
          !list? && !object?
        end

        # Returns `true` if this is a list type.
        #
        # Ignores any non-null wrapping on the type, if there is one.
        def list?
          name.start_with?("[")
        end

        # Returns `true` if this is a non-null type.
        def non_null?
          name.end_with?("!")
        end

        def boolean?
          name == "Boolean"
        end

        def to_s
          name
        end

        def resolved
          schema_def_state.types_by_name[name]
        end

        def unwrapped_name
          name
            .sub(/\A\[+/, "") # strip `[` characters from the start: https://rubular.com/r/tHVBBQkQUMMVVz
            .sub(/[\]!]+\z/, "") # strip `]` and `!` characters from the end: https://rubular.com/r/pC8C0i7EpvHDbf
        end

        # Generally speaking, scalar types have `grouped_by` fields which are scalars of the same types,
        # and object types have `grouped_by` fields which are special `[object_type]GroupedBy` types.
        #
        # ...except for some special cases (Date and DateTime), which this predicate detects.
        def scalar_type_needing_grouped_by_object?
          %w[Date DateTime].include?(type_namer.revert_override_for(name))
        end

        # Returns a new `TypeReference` with any type name overrides reverted (to provide the "original" type name).
        def with_reverted_override
          schema_def_state.type_ref(type_namer.revert_override_for(name))
        end

        # Returns all the JSON schema array/nullable layers of a type, from outermost to innermost.
        # For example, [[Int]] will return [:nullable, :array, :nullable, :array, :nullable]
        def json_schema_layers
          @json_schema_layers ||= begin
            layers, inner_type = peel_json_schema_layers_once

            if layers.empty? || inner_type == self
              layers
            else
              layers + inner_type.json_schema_layers
            end
          end
        end

        # Most of ElasticGraph's derived GraphQL types have a static suffix (e.g. the full type name
        # is source_type + suffix). This is a map of all of these.
        STATIC_FORMAT_NAME_BY_CATEGORY = TypeNamer::REQUIRED_PLACEHOLDERS.filter_map do |format_name, placeholders|
          if placeholders == [:base]
            as_snake_case = SchemaArtifacts::RuntimeMetadata::SchemaElementNamesDefinition::SnakeCaseConverter
              .normalize_case(format_name.to_s)
              .delete_prefix("_")

            [as_snake_case.to_sym, format_name]
          end
        end.to_h

        # Converts the TypeReference to its final form (i.e. the from that will be used in rendered schema artifacts).
        # This handles multiple bits of type name customization based on the configured `type_name_overrides` and
        # `derived_type_name_formats` settings (via the `TypeNamer`):
        #
        # - If the `as_input` is `true` and this is a reference to an enum type, converts to the `InputEnum` format.
        # - If there is a configured name override that applies to this type, uses it.
        def to_final_form(as_input: false)
          unwrapped = fully_unwrapped
          inner_name = type_namer.name_for(unwrapped.name)

          if as_input && schema_def_state.type_ref(inner_name).enum?
            inner_name = type_namer.name_for(
              type_namer.generate_name_for(:InputEnum, base: inner_name)
            )
          end

          renamed_with_same_wrappings(inner_name)
        end

        # Builds a `TypeReference` for a statically named derived type for the given `category.
        #
        # In addition, a dynamic method `as_[category]` is also provided (defined further below).
        def as_static_derived_type(category)
          renamed_with_same_wrappings(type_namer.generate_name_for(
            STATIC_FORMAT_NAME_BY_CATEGORY.fetch(category),
            base: fully_unwrapped.name
          ))
        end

        # Generates the type name used for a sub-aggregation. This type has `grouped_by`, `aggregated_values`,
        # `count` and `sub_aggregations` sub-fields to expose the different bits of aggregation functionality.
        #
        # The type name is based both on the type reference name and on the set of `parent_doc_types`
        # that exist above it. The `parent_doc_types` are used in the name because we plan to offer different sub-aggregations
        # under it based on where it is in the document structure. A type which is `nested` at multiple levels in different
        # document contexts needs separate types generated for each case so that we can offer the correct contextual
        # sub-aggregations that can be offered for each case.
        def as_sub_aggregation(parent_doc_types:)
          renamed_with_same_wrappings(type_namer.generate_name_for(
            :SubAggregation,
            base: fully_unwrapped.name,
            parent_types: parent_doc_types.join
          ))
        end

        # Generates the type name used for a `sub_aggregations` field. A `sub_aggregations` field is
        # available alongside `grouped_by`, `count`, and `aggregated_values` on an aggregation or
        # sub-aggregation node. This type is used in two situations:
        #
        # 1. It is used directly under `nodes`/`edges { node }` on an Aggregation or SubAggregation.
        #    It provides access to each of the sub-aggregations that are available in that context.
        # 2. It is used underneath that `SubAggregations` object for single object fields which have
        #    fields under them that are sub-aggregatable.
        #
        # The fields (and types of those fields) used for one of these types is contextual based on
        # what the parent doc types are (so that we can offer sub-aggregations of the parent doc types!)
        # and the field path (for the 2nd case).
        def as_aggregation_sub_aggregations(parent_doc_types: [fully_unwrapped.name], field_path: [])
          field_part = field_path.map { |f| to_title_case(f.name) }.join

          renamed_with_same_wrappings(type_namer.generate_name_for(
            :SubAggregations,
            parent_agg_type: parent_aggregation_type(parent_doc_types),
            field_path: field_part
          ))
        end

        def as_parent_aggregation(parent_doc_types:)
          schema_def_state.type_ref(parent_aggregation_type(parent_doc_types))
        end

        # Here we iterate over our mapping and generate dynamic methods for each category.
        STATIC_FORMAT_NAME_BY_CATEGORY.keys.each do |category|
          define_method(:"as_#{category}") do
            # @type self: TypeReference
            as_static_derived_type(category)
          end
        end

        def list_filter_input?
          matches_format_of?(:list_filter_input)
        end

        def list_element_filter_input?
          matches_format_of?(:list_element_filter_input)
        end

        # These methods are defined dynamically above:
        # @dynamic as_aggregated_values
        # @dynamic as_grouped_by
        # @dynamic as_aggregation
        # @dynamic as_connection
        # @dynamic as_edge
        # @dynamic as_fields_list_filter_input
        # @dynamic as_filter_input
        # @dynamic as_input_enum
        # @dynamic as_list_element_filter_input, list_element_filter_input?
        # @dynamic as_list_filter_input, list_filter_input?
        # @dynamic as_sort_order

        private

        def after_initialize
          Mixins::VerifiesGraphQLName.verify_name!(unwrapped_name)
        end

        def peel_json_schema_layers_once
          if list?
            return [[:array], unwrap_list] if non_null?
            return [[:nullable, :array], unwrap_list]
          end

          return [[], unwrap_non_null] if non_null?
          [[:nullable], self]
        end

        def matches_format_of?(category)
          format_name = STATIC_FORMAT_NAME_BY_CATEGORY.fetch(category)
          type_namer.matches_format?(name, format_name)
        end

        def parent_aggregation_type(parent_doc_types)
          __skip__ = case parent_doc_types
          in [single_parent_type]
            type_namer.generate_name_for(:Aggregation, base: single_parent_type)
          in [*parent_types, last_parent_type]
            type_namer.generate_name_for(:SubAggregation, parent_types: parent_types.join, base: last_parent_type)
          else
            raise Errors::SchemaError, "Unexpected `parent_doc_types`: #{parent_doc_types.inspect}. `parent_doc_types` must not be empty."
          end
        end

        def renamed_with_same_wrappings(new_name)
          pre_wrappings, post_wrappings = name.split(GRAPHQL_NAME_WITHIN_LARGER_STRING_PATTERN)
          schema_def_state.type_ref("#{pre_wrappings}#{new_name}#{post_wrappings}")
        end

        ENUM_FORMATS = TypeNamer::DEFINITE_ENUM_FORMATS
        OBJECT_FORMATS = TypeNamer::DEFINITE_OBJECT_FORMATS

        def schema_kind_implied_by_name
          name = type_namer.revert_override_for(self.name)
          return :enum if ENUM_FORMATS.any? { |f| type_namer.matches_format?(name, f) }
          return :object if OBJECT_FORMATS.any? { |f| type_namer.matches_format?(name, f) }

          if (as_output_enum_name = type_namer.extract_base_from(name, format: :InputEnum))
            :enum if ENUM_FORMATS.any? { |f| type_namer.matches_format?(as_output_enum_name, f) }
          end
        end

        def to_title_case(name)
          CamelCaseConverter.normalize_case(name).sub(/\A(\w)/, &:upcase)
        end

        CamelCaseConverter = SchemaArtifacts::RuntimeMetadata::SchemaElementNamesDefinition::CamelCaseConverter
      end
    end
  end
end
