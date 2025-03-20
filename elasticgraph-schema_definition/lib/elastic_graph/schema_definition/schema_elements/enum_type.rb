# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/enum"
require "elastic_graph/schema_definition/indexing/field_type/enum"
require "elastic_graph/schema_definition/mixins/can_be_graphql_only"
require "elastic_graph/schema_definition/mixins/has_derived_graphql_type_customizations"
require "elastic_graph/schema_definition/mixins/has_directives"
require "elastic_graph/schema_definition/mixins/has_documentation"
require "elastic_graph/schema_definition/mixins/has_readable_to_s_and_inspect"
require "elastic_graph/schema_definition/mixins/verifies_graphql_name"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # {include:API#enum_type}
      #
      # @example Define an enum type
      #   ElasticGraph.define_schema do |schema|
      #     schema.enum_type "Currency" do |t|
      #       # in the block, `t` is an EnumType
      #       t.value "USD"
      #     end
      #   end
      #
      # @!attribute [r] schema_def_state
      #   @return [State] state of the schema
      # @!attribute [rw] type_ref
      #   @private
      # @!attribute [rw] for_output
      #   @return [Boolean] `true` if this enum is used for both input and output; `false` if it is for input only
      # @!attribute [r] values_by_name
      #   @return [Hash<String, EnumValue>] map of enum values, keyed by name
      class EnumType < Struct.new(:schema_def_state, :type_ref, :for_output, :values_by_name)
        # @dynamic type_ref, graphql_only?
        prepend Mixins::VerifiesGraphQLName
        include Mixins::CanBeGraphQLOnly
        include Mixins::HasDocumentation
        include Mixins::HasDirectives
        include Mixins::HasDerivedGraphQLTypeCustomizations
        include Mixins::HasReadableToSAndInspect.new { |e| e.name }

        # @private
        def initialize(schema_def_state, name)
          # @type var values_by_name: ::Hash[::String, EnumValue]
          values_by_name = {}
          super(schema_def_state, schema_def_state.type_ref(name).to_final_form, true, values_by_name)

          # :nocov: -- currently all invocations have a block
          yield self if block_given?
          # :nocov:
        end

        # @return [String] name of the enum type
        def name
          type_ref.name
        end

        # @return [TypeReference] reference to `AggregatedValues` type to use for this enum.
        def aggregated_values_type
          schema_def_state.type_ref("NonNumeric").as_aggregated_values
        end

        # Defines an enum value for the current enum type.
        #
        # @param value_name [String] name of the enum value
        # @yield [EnumValue] enum value so it can be further customized
        # @return [void]
        #
        # @example Define an enum type with multiple enum values
        #   ElasticGraph.define_schema do |schema|
        #     schema.enum_type "Currency" do |t|
        #       t.value "USD" do |v|
        #         v.documentation "US Dollars."
        #       end
        #
        #       t.value "JPY" do |v|
        #         v.documentation "Japanese Yen."
        #       end
        #     end
        #   end
        def value(value_name, &block)
          alternate_original_name = value_name
          value_name = schema_def_state.enum_value_namer.name_for(name, value_name.to_s)

          if values_by_name.key?(value_name)
            raise Errors::SchemaError, "Duplicate value on Enum::Type #{name}: #{value_name}"
          end

          if value_name.length > DEFAULT_MAX_KEYWORD_LENGTH
            raise Errors::SchemaError, "Enum value `#{name}.#{value_name}` is too long: it is #{value_name.length} characters but cannot exceed #{DEFAULT_MAX_KEYWORD_LENGTH} characters."
          end

          values_by_name[value_name] = schema_def_state.factory.new_enum_value(value_name, alternate_original_name, &block)
        end

        # Defines multiple enum values. In contrast to {#value}, the enum values cannot be customized
        # further via a block.
        #
        # @param value_names [Array<String>] names of the enum values
        # @return [void]
        #
        # @example Define an enum type with multiple enum values
        #   ElasticGraph.define_schema do |schema|
        #     schema.enum_type "Currency" do |t|
        #       t.values "USD", "JPY", "CAD", "GBP"
        #     end
        #   end
        def values(*value_names)
          value_names.flatten.each { |name| value(name) }
        end

        # @return [SchemaArtifacts::RuntimeMetadata::Enum::Type] runtime metadata for this enum type
        def runtime_metadata
          runtime_metadata_values_by_name = values_by_name
            .transform_values(&:runtime_metadata)
            .compact

          SchemaArtifacts::RuntimeMetadata::Enum::Type.new(values_by_name: runtime_metadata_values_by_name)
        end

        # @return [String] GraphQL SDL form of the enum type
        def to_sdl
          if values_by_name.empty?
            raise Errors::SchemaError, "Enum type #{name} has no values, but enums must have at least one value."
          end

          <<~EOS
            #{formatted_documentation}enum #{name} #{directives_sdl(suffix_with: " ")}{
              #{values_by_name.values.map(&:to_sdl).flat_map { |s| s.split("\n") }.join("\n  ")}
            }
          EOS
        end

        # @private
        def derived_graphql_types
          # Derived GraphQL types must be generated for an output enum. For an enum type that is only
          # used as an input, we do not need derived types.
          return [] unless for_output

          derived_scalar_types = schema_def_state.factory.new_scalar_type(name) do |t|
            t.mapping type: "keyword"
            t.json_schema type: "string"
            t.graphql_only graphql_only?
          end.derived_graphql_types

          if (input_enum = as_input).equal?(self)
            derived_scalar_types
          else
            [input_enum] + derived_scalar_types
          end
        end

        # @return [Indexing::FieldType::Enum] indexing representation of this enum type
        def to_indexing_field_type
          Indexing::FieldType::Enum.new(values_by_name.keys)
        end

        # @return [false] enum types are never directly indexed
        def indexed?
          false
        end

        # @return [EnumType] converts the enum type to its input form for when different naming is used for input vs output enums.
        def as_input
          input_name = type_ref
            .as_input_enum # To apply the configured format for input enums.
            .to_final_form # To handle a type name override of the input enum.
            .name

          return self if input_name == name

          schema_def_state.factory.new_enum_type(input_name) do |t|
            t.for_output = false # flag that it's not used as an output enum, and therefore `derived_graphql_types` will be empty on it.
            t.graphql_only true # input enums are always GraphQL-only.
            t.documentation doc_comment
            directives.each { |dir| dir.duplicate_on(t) }
            values_by_name.each { |_, val| val.duplicate_on(t) }
          end
        end
      end
    end
  end
end
