# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/protobuf/schema_definition/field_type_converter"
require "elastic_graph/protobuf/schema_definition/identifier"

module ElasticGraph
  module Protobuf
    # Protocol Buffers schema-generation support for ElasticGraph schema-definition results.
    module SchemaDefinition
      # Builds a `proto3` schema string from an ElasticGraph schema definition.
      class Schema
        # Internal representation of a protobuf field definition.
        #
        # @!attribute [r] name
        #   @return [String]
        # @!attribute [r] type
        #   @return [String]
        # @!attribute [r] field_number
        #   @return [Integer]
        # @!attribute [r] repeated
        #   @return [Boolean]
        # @!attribute [r] comment
        #   @return [String, nil]
        FieldDefinition = ::Data.define(:name, :type, :field_number, :repeated, :comment)
        # Internal representation of a protobuf message definition.
        #
        # @!attribute [r] name
        #   @return [String]
        # @!attribute [r] fields
        #   @return [Array<FieldDefinition>]
        MessageDefinition = ::Data.define(:name, :fields)
        # Internal representation of a protobuf enum value definition.
        #
        # @!attribute [r] name
        #   @return [String]
        # @!attribute [r] number
        #   @return [Integer]
        EnumValueDefinition = ::Data.define(:name, :number)
        # Internal representation of a protobuf enum definition.
        #
        # @!attribute [r] name
        #   @return [String]
        # @!attribute [r] zero_value_name
        #   @return [String]
        # @!attribute [r] values
        #   @return [Array<EnumValueDefinition>]
        EnumDefinition = ::Data.define(:name, :zero_value_name, :values)
        # Internal representation of a stored field-number mapping.
        #
        # @!attribute [r] field_number
        #   @return [Integer]
        # @!attribute [r] name_in_index
        #   @return [String]
        FieldNumberMapping = ::Data.define(:field_number, :name_in_index)

        # Generates the full `proto3` schema text for indexed types.
        #
        # @param results [ElasticGraph::SchemaDefinition::Results]
        # @param package_name [String]
        # @param proto_enums_by_graphql_enum [Hash]
        # @param proto_field_number_mappings [Hash]
        # @return [String]
        def self.generate(
          results,
          package_name: "elasticgraph",
          proto_enums_by_graphql_enum: {},
          proto_field_number_mappings: {}
        )
          new(
            results,
            package_name: package_name,
            proto_enums_by_graphql_enum: proto_enums_by_graphql_enum,
            proto_field_number_mappings: proto_field_number_mappings
          ).to_proto
        end

        def initialize(
          results,
          package_name:,
          proto_enums_by_graphql_enum:,
          proto_field_number_mappings: {}
        )
          @results = results
          @package_name = Identifier.package_name(package_name)
          @proto_enums_by_graphql_enum = normalize_proto_enum_mappings(proto_enums_by_graphql_enum)
          @proto_field_number_mappings_by_message = normalize_proto_field_number_mappings(proto_field_number_mappings)
          @message_definitions_by_name = {}
          @enum_definitions_by_name = {}
          @generated_message_definitions_by_name = {}
          @wrapper_root_name_by_context = {}
          @type_name_by_message_name = {}
          @type_name_by_enum_name = {}
        end

        # Renders the schema as a valid `proto3` file.
        #
        # @return [String]
        def to_proto
          root_types = indexed_types
          return "" if root_types.empty?

          root_types.each { |type| register_type(type) }

          sections = [
            'syntax = "proto3";',
            "package #{@package_name};",
            render_definitions
          ]

          sections.join("\n\n") + "\n"
        end

        private

        def indexed_types
          types = @results.schema_artifact_types

          types
            .filter_map { |type| (_ = type).index_def if type.respond_to?(:index_def) }
            .map(&:indexed_type)
            .uniq(&:name)
            .sort_by(&:name)
        end

        def register_type(type)
          if type.respond_to?(:values_by_name)
            register_enum(type)
          elsif type.respond_to?(:indexing_fields_by_name_in_index)
            register_message(type)
          elsif type.respond_to?(:to_proto_field_type)
            type.to_proto_field_type
          else
            raise Errors::SchemaError, "Type `#{type.respond_to?(:name) ? type.name : type.inspect}` cannot be converted to proto."
          end
        end

        def register_type_ref(type_ref)
          _list_depth, base_type_ref = list_depth_and_base_type(type_ref)

          resolved = base_type_ref.resolved
          if resolved.nil?
            raise Errors::SchemaError, "Type `#{base_type_ref.unwrapped_name}` cannot be resolved for proto generation."
          end

          register_type(resolved)
        end

        def register_message(type)
          message_name = Identifier.message_name(type.name)
          check_message_name_collision(message_name, type.name)
          return if @message_definitions_by_name.key?(message_name)

          # Register a placeholder first so recursive type references do not recurse forever.
          @message_definitions_by_name[message_name] = MessageDefinition.new(name: message_name, fields: [])

          fields = type
            .indexing_fields_by_name_in_index
            .values
            .filter_map(&:to_indexing_field)
            .map do |field|
              field_name = Identifier.field_name(field.name)
              repeated, field_type = proto_field_type_for(
                field.type,
                context_message_name: message_name,
                context_field_name: field.name
              )
              field_number = field_number_for(
                message_name: message_name,
                type_name: type.name,
                public_field_name: field.name,
                name_in_index: field.name_in_index
              )

              comment =
                if field_name == field.name
                  nil
                else
                  "source name: #{field.name}"
                end

              FieldDefinition.new(
                name: field_name,
                type: field_type,
                field_number: field_number,
                repeated: repeated,
                comment: comment
              )
            end

          duplicate_names = fields.group_by(&:name).select { |_, defs| defs.size > 1 }
          if duplicate_names.any?
            duplicates = duplicate_names.keys.sort.join(", ")
            raise Errors::SchemaError, "Type `#{type.name}` maps to duplicate proto field names: #{duplicates}."
          end

          @message_definitions_by_name[message_name] = MessageDefinition.new(name: message_name, fields: fields)
        end

        def register_enum(enum_type)
          enum_name = Identifier.enum_name(enum_type.name)
          check_enum_name_collision(enum_name, enum_type.name)
          return if @enum_definitions_by_name.key?(enum_name)

          values = enum_value_names_for(enum_type).each_with_index.map do |enum_value_name, i|
            EnumValueDefinition.new(
              name: proto_enum_value_name(enum_type.name, enum_value_name),
              number: i + 1
            )
          end

          duplicate_names = values.group_by(&:name).select { |_, defs| defs.size > 1 }
          if duplicate_names.any?
            duplicates = duplicate_names.keys.sort.join(", ")
            raise Errors::SchemaError, "Enum `#{enum_type.name}` maps to duplicate proto enum value names: #{duplicates}."
          end

          zero_value_name = proto_zero_enum_value_name(enum_type.name)
          while values.any? { |value| value.name == zero_value_name }
            zero_value_name = "#{zero_value_name}_"
          end

          @enum_definitions_by_name[enum_name] = EnumDefinition.new(
            name: enum_name,
            zero_value_name: zero_value_name,
            values: values
          )
        end

        def enum_value_names_for(enum_type)
          mapping_entries = @proto_enums_by_graphql_enum[enum_type.name]
          return enum_type.values_by_name.keys if mapping_entries.nil? || mapping_entries.empty?

          values_by_source = mapping_entries.map do |proto_type, options|
            enum_value_names_from_proto_mapping(enum_type_name: enum_type.name, proto_type: proto_type, options: options || {})
          end

          canonical_values = values_by_source.first
          canonical_set = canonical_values.uniq.sort

          values_by_source.drop(1).each do |source_values|
            next if source_values.uniq.sort == canonical_set

            raise Errors::SchemaError, "Protobuf enum mappings for `#{enum_type.name}` produce inconsistent value sets. " \
              "Ensure each mapped proto enum (with exclusions/expected_extras/name_transform) resolves to the same values."
          end

          canonical_values
        end

        def enum_value_names_from_proto_mapping(enum_type_name:, proto_type:, options:)
          unless proto_type.respond_to?(:enums)
            raise Errors::SchemaError, "Protobuf enum mapping for `#{enum_type_name}` must map to a proto enum class with `.enums`, " \
              "but got: #{proto_type.inspect}."
          end

          name_transform = fetch_mapping_option(options, :name_transform, :itself.to_proc)
          exclusions = fetch_mapping_option(options, :exclusions, []).map(&:to_s)
          expected_extras = fetch_mapping_option(options, :expected_extras, []).map(&:to_s)

          mapped_values = proto_type.enums.map(&:name).map(&:to_s).map do |name|
            transformed = name_transform.call(name)
            transformed.to_s
          end

          (mapped_values - exclusions + expected_extras).uniq
        rescue Errors::SchemaError
          raise
        rescue => e
          raise Errors::SchemaError, "Failed loading proto enum mapping for `#{enum_type_name}` from `#{proto_type}`: #{e.message}"
        end

        def field_number_for(message_name:, type_name:, public_field_name:, name_in_index:)
          mappings_for_message = @proto_field_number_mappings_by_message[message_name] ||= {}

          mapping =
            if mappings_for_message.key?(public_field_name)
              mappings_for_message.fetch(public_field_name)
            else
              migrate_renamed_field_mapping(
                mappings_for_message,
                type_name: type_name,
                public_field_name: public_field_name
              ) || begin
                next_field_number = next_available_field_number_for(mappings_for_message)
                FieldNumberMapping.new(field_number: next_field_number, name_in_index: name_in_index)
              end
            end

          if mapping.name_in_index != name_in_index
            mapping = FieldNumberMapping.new(field_number: mapping.field_number, name_in_index: name_in_index)
          end

          mappings_for_message[public_field_name] = mapping
          field_number = mapping.field_number

          duplicate_field_name = mappings_for_message.find do |mapped_field_name, mapped_field_number|
            mapped_field_name != public_field_name && mapped_field_number.field_number == field_number
          end&.first

          if duplicate_field_name
            raise Errors::SchemaError, "Protobuf field-number mapping collision in message `#{message_name}`: " \
              "`#{duplicate_field_name}` and `#{public_field_name}` are both mapped to field number #{field_number}."
          end

          field_number
        end

        def next_available_field_number_for(mappings_for_message)
          used_numbers = ::Set.new(mappings_for_message.values.map(&:field_number))
          candidate = 1
          candidate += 1 while used_numbers.include?(candidate)
          candidate
        end

        def migrate_renamed_field_mapping(mappings_for_message, type_name:, public_field_name:)
          old_field_names =
            renamed_public_field_names_by_type_name
              .fetch(type_name, {})
              .fetch(public_field_name, [])

          old_field_names.each do |old_field_name|
            return mappings_for_message.delete(old_field_name) if mappings_for_message.key?(old_field_name)
          end

          nil
        end

        public

        # Exposes normalized field-number mappings for writing to artifact YAML.
        #
        # @return [Hash<String, Hash<String, Hash<String, Integer>>>]
        def field_number_mappings_for_artifact
          {
            "messages" => @proto_field_number_mappings_by_message
              .sort_by { |message_name, _| message_name }
              .to_h do |message_name, field_numbers|
                [message_name, {
                  "fields" => field_numbers.sort_by { |field_name, mapping| [mapping.field_number, field_name] }.to_h do |field_name, mapping|
                    artifact_mapping =
                      if mapping.name_in_index == field_name
                        mapping.field_number
                      else
                        {
                          "field_number" => mapping.field_number,
                          "name_in_index" => mapping.name_in_index
                        }
                      end

                    [field_name, artifact_mapping]
                  end
                }]
              end
          }
        end

        private

        def proto_field_type_for(type_ref, context_message_name:, context_field_name:)
          list_depth, base_type_ref = list_depth_and_base_type(type_ref)
          register_type_ref(base_type_ref)

          base_type_name = FieldTypeConverter.convert(base_type_ref)

          if list_depth <= 1
            [list_depth == 1, base_type_name]
          else
            wrapper_type = register_nested_list_wrappers(
              context_message_name: context_message_name,
              context_field_name: context_field_name,
              list_depth: list_depth,
              base_type_name: base_type_name
            )

            [true, wrapper_type]
          end
        end

        def list_depth_and_base_type(type_ref)
          list_depth = 0
          current = type_ref.unwrap_non_null

          while current.list?
            list_depth += 1
            current = current.unwrap_list.unwrap_non_null
          end

          [list_depth, current]
        end

        def register_nested_list_wrappers(context_message_name:, context_field_name:, list_depth:, base_type_name:)
          context_key = [context_message_name, context_field_name, list_depth, base_type_name]
          existing_root = @wrapper_root_name_by_context[context_key]
          return existing_root if existing_root

          next_type_name = base_type_name
          root_wrapper_name = nil

          (list_depth - 1).downto(1) do |level|
            base_wrapper_name = "#{context_message_name}#{to_title_case(context_field_name)}ListLevel#{level}"
            wrapper_name = unique_generated_message_name(base_wrapper_name)

            field = FieldDefinition.new(
              name: "values",
              type: next_type_name,
              field_number: 1,
              repeated: true,
              comment: nil
            )

            @generated_message_definitions_by_name[wrapper_name] = MessageDefinition.new(
              name: wrapper_name,
              fields: [field]
            )

            next_type_name = wrapper_name
            root_wrapper_name = wrapper_name if level == 1
          end

          @wrapper_root_name_by_context[context_key] = root_wrapper_name
        end

        def unique_generated_message_name(base_name)
          index = 0

          loop do
            candidate_name =
              if index.zero?
                Identifier.message_name(base_name)
              else
                Identifier.message_name("#{base_name}#{index + 1}")
              end

            return candidate_name unless name_taken?(candidate_name)
            index += 1
          end
        end

        def name_taken?(name)
          @message_definitions_by_name.key?(name) ||
            @generated_message_definitions_by_name.key?(name) ||
            @enum_definitions_by_name.key?(name)
        end

        def render_definitions
          rendered_enums = all_enum_definitions.sort_by(&:name).map { |definition| render_enum(definition) }
          rendered_messages = all_message_definitions.sort_by(&:name).map { |definition| render_message(definition) }
          (rendered_enums + rendered_messages).join("\n\n")
        end

        def proto_enum_value_name(enum_type_name, enum_value_name)
          Identifier.enum_value_name("#{enum_value_prefix(enum_type_name)}_#{to_upper_snake_case(enum_value_name)}")
        end

        def proto_zero_enum_value_name(enum_type_name)
          "#{enum_value_prefix(enum_type_name)}_UNSPECIFIED"
        end

        def enum_value_prefix(enum_type_name)
          to_upper_snake_case(enum_type_name)
        end

        def render_enum(enum_definition)
          lines = [
            "enum #{enum_definition.name} {",
            "  #{enum_definition.zero_value_name} = 0;"
          ]

          enum_definition.values.each do |value|
            lines << "  #{value.name} = #{value.number};"
          end

          lines << "}"
          lines.join("\n")
        end

        def render_message(message_definition)
          lines = ["message #{message_definition.name} {"]

          if message_definition.fields.empty?
            lines << "  // No indexed fields were defined for this type."
          else
            message_definition.fields.each do |field|
              repeated_modifier = field.repeated ? "repeated " : ""
              line = "  #{repeated_modifier}#{field.type} #{field.name} = #{field.field_number};"
              line += " // #{field.comment}" if field.comment
              lines << line
            end
          end

          lines << "}"
          lines.join("\n")
        end

        def all_enum_definitions
          @enum_definitions_by_name.values
        end

        def all_message_definitions
          @message_definitions_by_name.values + @generated_message_definitions_by_name.values
        end

        def to_title_case(name)
          name
            .gsub(/([[:lower:]\d])([[:upper:]])/, "\\1_\\2")
            .split("_")
            .reject(&:empty?)
            .map(&:capitalize)
            .join
        end

        def to_upper_snake_case(name)
          name
            .to_s
            .gsub(/([[:upper:]]+)([[:upper:]][[:lower:]])/, "\\1_\\2")
            .gsub(/([[:lower:]\d])([[:upper:]])/, "\\1_\\2")
            .upcase
        end

        def check_message_name_collision(message_name, type_name)
          existing_type_name = @type_name_by_message_name.fetch(message_name, type_name)
          @type_name_by_message_name[message_name] = existing_type_name
          return if existing_type_name == type_name

          raise Errors::SchemaError, "Type names `#{existing_type_name}` and `#{type_name}` both map to the same proto message name `#{message_name}`."
        end

        def check_enum_name_collision(enum_name, type_name)
          existing_type_name = @type_name_by_enum_name.fetch(enum_name, type_name)
          @type_name_by_enum_name[enum_name] = existing_type_name
          return if existing_type_name == type_name

          raise Errors::SchemaError, "Type names `#{existing_type_name}` and `#{type_name}` both map to the same proto enum name `#{enum_name}`."
        end

        def normalize_proto_enum_mappings(raw_mappings)
          return {} if raw_mappings.nil?

          raw_mappings.each_with_object({}) do |(graphql_enum_name, mappings), normalized|
            normalized[graphql_enum_name.to_s] = mappings
          end
        end

        def normalize_proto_field_number_mappings(raw_mappings)
          return {} if raw_mappings.nil?
          unless raw_mappings.is_a?(Hash)
            raise Errors::SchemaError, "Protobuf field-number mappings must be a Hash, got: #{raw_mappings.class}."
          end

          messages_hash =
            if raw_mappings.key?("messages")
              raw_mappings.fetch("messages")
            elsif raw_mappings.key?(:messages)
              raw_mappings.fetch(:messages)
            else
              raw_mappings
            end

          unless messages_hash.is_a?(Hash)
            raise Errors::SchemaError, "Protobuf field-number mappings must have a `messages` Hash."
          end

          messages_hash.each_with_object({}) do |(message_name, field_numbers), normalized|
            unless field_numbers.is_a?(Hash)
              raise Errors::SchemaError, "Field-number mapping for message `#{message_name}` must be a Hash."
            end

            normalized_fields =
              if field_numbers.key?("fields")
                field_numbers.fetch("fields")
              elsif field_numbers.key?(:fields)
                field_numbers.fetch(:fields)
              else
                field_numbers
              end

            unless normalized_fields.is_a?(Hash)
              raise Errors::SchemaError, "Field-number mapping for message `#{message_name}` must contain a `fields` Hash."
            end

            normalized_message_name = message_name.to_s
            normalized[normalized_message_name] = normalized_fields.each_with_object({}) do |(field_name, field_number_or_mapping), normalized_field_numbers|
              normalized_field_name = field_name.to_s
              normalized_field_number, normalized_name_in_index = normalize_field_number_mapping_entry(
                normalized_message_name,
                normalized_field_name,
                field_number_or_mapping
              )

              if normalized_field_number <= 0
                raise Errors::SchemaError, "Field-number mapping for `#{normalized_message_name}.#{normalized_field_name}` " \
                  "must be a positive integer, got: #{field_number_or_mapping.inspect}."
              end

              normalized_field_numbers[normalized_field_name] = FieldNumberMapping.new(
                field_number: normalized_field_number,
                name_in_index: normalized_name_in_index
              )
            rescue ArgumentError, TypeError
              raise Errors::SchemaError, "Field-number mapping for `#{normalized_message_name}.#{normalized_field_name}` " \
                "must be an integer, got: #{field_number_or_mapping.inspect}."
            end
          end
        end

        def normalize_field_number_mapping_entry(message_name, field_name, field_number_or_mapping)
          if field_number_or_mapping.is_a?(Hash)
            raw_field_number =
              if field_number_or_mapping.key?("field_number")
                field_number_or_mapping.fetch("field_number")
              elsif field_number_or_mapping.key?(:field_number)
                field_number_or_mapping.fetch(:field_number)
              else
                raise Errors::SchemaError, "Field-number mapping for `#{message_name}.#{field_name}` must include `field_number`."
              end

            raw_name_in_index =
              if field_number_or_mapping.key?("name_in_index")
                field_number_or_mapping.fetch("name_in_index")
              elsif field_number_or_mapping.key?(:name_in_index)
                field_number_or_mapping.fetch(:name_in_index)
              else
                field_name
              end

            unless raw_name_in_index.is_a?(String) || raw_name_in_index.is_a?(Symbol)
              raise Errors::SchemaError, "Field-number mapping for `#{message_name}.#{field_name}` " \
                "must use a String or Symbol `name_in_index`, got: #{raw_name_in_index.inspect}."
            end

            [Integer(raw_field_number), raw_name_in_index.to_s]
          else
            [Integer(field_number_or_mapping), field_name]
          end
        end

        def renamed_public_field_names_by_type_name
          @renamed_public_field_names_by_type_name ||= begin
            renamed_fields_by_type_name_and_old_field_name =
              if @results.respond_to?(:state) && @results.state.respond_to?(:renamed_fields_by_type_name_and_old_field_name)
                @results.state.renamed_fields_by_type_name_and_old_field_name
              else
                {}
              end

            renamed_fields_by_type_name_and_old_field_name.each_with_object({}) do |(type_name, old_to_new), mappings|
              mappings[type_name] = old_to_new.each_with_object(::Hash.new { |h, k| h[k] = [] }) do |(old_field_name, renamed_field), current_to_old|
                current_to_old[renamed_field.name] << old_field_name
              end
            end
          end
        end

        def fetch_mapping_option(options, key, default)
          if options.key?(key)
            options[key]
          elsif options.key?(key.to_s)
            options[key.to_s]
          else
            default
          end
        end
      end
    end
  end
end
