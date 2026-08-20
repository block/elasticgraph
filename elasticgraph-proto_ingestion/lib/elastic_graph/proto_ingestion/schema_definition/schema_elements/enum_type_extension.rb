# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/proto_documentation"
require "elastic_graph/support/casing"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Protobuf schema definition extensions for ElasticGraph schema elements.
      module SchemaElements
        # Extends EnumType with proto field type conversion.
        module EnumTypeExtension
          # Describes an external proto enum registered as the source of this enum's generated values.
          ExternalProtoEnumSource = ::Data.define(:proto_enum, :exclusions, :expected_extras, :name_transform)

          # Describes an existing proto enum type referenced instead of generating a local definition.
          ExternalProtoEnumReference = ::Data.define(:proto_name, :import)

          # Sources this enum's generated proto values from an existing proto enum class. Passing
          # `proto:` and `import:` references that enum directly instead of generating a local enum.
          #
          # `name_transform` runs first, and `exclusions` and `expected_extras` then apply to the
          # transformed names. Order matters: with a transform that strips a `CURRENCY_` prefix, an
          # exclusion must be written as `UNKNOWN` rather than `CURRENCY_UNKNOWN`.
          #
          # @param proto_enum [Object] proto enum class, or anything else exposing `.enums`
          # @param exclusions [Array<String, Symbol>] transformed value names to omit from the generated enum
          # @param expected_extras [Array<String, Symbol>] value names to add that the proto enum lacks
          # @param name_transform [Proc, nil] applied to each proto value name before the options above
          # @param proto [String, nil] fully qualified name of an existing proto enum to reference
          # @param import [String, nil] proto file that defines the referenced enum
          # @return [void]
          # @raise [Errors::SchemaError] when the arguments cannot produce a valid proto enum
          #
          # @example Source values from a proto enum, transforming and curating them
          #   ElasticGraph.define_schema do |schema|
          #     schema.enum_type "Currency" do |t|
          #       t.values "USD", "CAD"
          #       t.external_proto_enum MyApp::Protos::Currency,
          #         exclusions: [:UNKNOWN_DO_NOT_USE],
          #         name_transform: ->(name) { name.delete_prefix("CURRENCY_") }
          #     end
          #   end
          def external_proto_enum(proto_enum, exclusions: [], expected_extras: [], name_transform: nil, proto: nil, import: nil)
            unless proto_enum.respond_to?(:enums)
              raise Errors::SchemaError, "`external_proto_enum` on `#{name}` must be given a proto enum class with `.enums`, " \
                "but got: #{proto_enum.inspect}."
            end

            if proto || import
              unless proto.is_a?(String) && !proto.empty? && import.is_a?(String) && !import.empty?
                raise Errors::SchemaError, "`external_proto_enum` on `#{name}` must be given both `proto` and `import` " \
                  "as non-empty Strings to reference an external proto enum type."
              end
              unless exclusions.empty? && expected_extras.empty? && name_transform.nil?
                raise Errors::SchemaError, "`external_proto_enum` on `#{name}` cannot combine `proto`/`import` with " \
                  "`exclusions`, `expected_extras`, or `name_transform`; transformed or curated enums must stay generated locally."
              end

              @external_proto_reference = ExternalProtoEnumReference.new(proto_name: proto, import: import)
            end

            external_proto_enum_sources << ExternalProtoEnumSource.new(
              proto_enum: proto_enum,
              exclusions: exclusions.map(&:to_s),
              expected_extras: expected_extras.map(&:to_s),
              name_transform: name_transform
            )
            nil
          end

          # External proto enums registered via {#external_proto_enum}.
          #
          # @return [Array<ExternalProtoEnumSource>]
          def external_proto_enum_sources
            @external_proto_enum_sources ||= []
          end

          # The external proto enum type referenced instead of generating a local enum, if configured.
          #
          # @dynamic external_proto_reference
          # @return [ExternalProtoEnumReference, nil]
          attr_reader :external_proto_reference

          # Defines an enum value and immediately validates its protobuf name.
          #
          # @return [void]
          def value(value_name)
            super(value_name) do |new_value|
              new_proto_name = new_value.proto_name(proto_enum_value_prefix)

              if new_proto_name == proto_zero_value_name
                raise Errors::SchemaError, "Enum `#{name}` value `#{new_value.name}` maps to proto enum value name " \
                  "`#{new_proto_name}`, which conflicts with the generated zero value `#{proto_zero_value_name}`."
              end

              if (duplicate = values_by_proto_name[new_proto_name])
                raise Errors::SchemaError, "Enum `#{name}` values `#{duplicate.name}` and `#{new_value.name}` " \
                  "map to duplicate proto enum value name `#{new_proto_name}`."
              end

              yield new_value if block_given?
              values_by_proto_name[new_proto_name] = new_value
            end
          end

          # Renders this enum's protobuf definition, or `nil` when the enum references an external
          # proto type and therefore contributes no local definition to `schema.proto`. Rendering is
          # also where an external reference is checked and its numbers are recorded, because both
          # need the `schema`'s field-number mappings.
          #
          # @return [String, nil]
          def to_proto(schema, _package_name)
            if external_proto_reference
              validate_external_proto_reference(schema)
              return nil
            end

            render_proto_enum(schema)
          end

          # Returns the schema types referenced by this definition.
          #
          # @return [Array]
          def referenced_proto_types
            []
          end

          # Returns this enum type's name in protobuf schemas.
          #
          # @return [String]
          def proto_name
            external_proto_reference&.proto_name || name
          end

          # Returns the fully qualified name used to reference this enum from protobuf fields.
          #
          # @return [String]
          def proto_type_reference(package_name)
            external_proto_reference ? proto_name : ".#{package_name}.#{proto_name}"
          end

          # Returns the proto file imported for an externally referenced enum.
          #
          # @return [String, nil]
          def protobuf_import
            external_proto_reference&.import
          end

          # Enum values are self-describing, so fields of this type get no format comment.
          # Only scalar types document a format.
          #
          # @return [nil]
          def protobuf_field_comment
            nil
          end

          # Returns the package-level prefix applied to this enum's protobuf values.
          #
          # @return [String]
          def proto_enum_value_prefix
            @proto_enum_value_prefix ||= Support::Casing.to_upper_snake(name)
          end

          # @private
          def configure_derived_scalar_type(scalar_type)
            super
            proto_scalar_type = scalar_type # : ::ElasticGraph::SchemaDefinition::SchemaElements::ScalarType & ScalarTypeExtension
            proto_scalar_type.protobuf type: proto_name
          end

          private

          def render_proto_enum(schema)
            documentation = ProtoDocumentation.comment_lines_for(doc_comment).map { |line| "#{line}\n" }.join
            source_value_names = proto_enum_value_names
            proto_value_names_by_source_name = source_value_names.to_h do |source_name|
              [source_name, proto_enum_value_name(source_name)]
            end
            duplicate_names = proto_value_names_by_source_name.values.tally.select { |_, count| count > 1 }
            if duplicate_names.any?
              raise Errors::SchemaError, "Enum `#{name}` maps to duplicate proto enum value names: #{duplicate_names.keys.sort.join(", ")}."
            end

            if (source_name = proto_value_names_by_source_name.key(proto_zero_value_name))
              raise Errors::SchemaError, "Enum `#{name}` value `#{source_name}` maps to proto enum value name " \
                "`#{proto_zero_value_name}`, which conflicts with the generated zero value `#{proto_zero_value_name}`."
            end

            value_numbers = schema.enum_value_numbers_for(proto_name, source_value_names)
            value_definitions = [proto_zero_value.to_proto(0, proto_enum_value_prefix: proto_enum_value_prefix)]
            value_definitions.concat(proto_value_names_by_source_name.map do |source_name, proto_value_name|
              if (raw_value = values_by_name[source_name])
                value = raw_value # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumValue & EnumValueExtension
                value.to_proto(value_numbers.fetch(source_name), proto_enum_value_prefix: proto_enum_value_prefix)
              else
                "  #{proto_value_name} = #{value_numbers.fetch(source_name)};"
              end
            end)
            # The active set must be the names we just emitted, not `values_by_name.keys`. An
            # externally sourced name (such as an `expected_extras` entry) is emitted here but has
            # no ElasticGraph enum value, so keying off `values_by_name` would reserve the very
            # number the emitted value uses -- which protoc rejects.
            schema.reserved_enum_value_numbers_for(proto_name, source_value_names).each do |value_name, value_number|
              value_definitions << "  reserved #{value_number}; // Previously used by #{value_name}."
            end
            value_definitions << "  // Next value number: #{schema.next_enum_value_number_for(proto_name)}"

            <<~PROTO.chomp
              #{documentation}enum #{proto_name} {
              #{value_definitions.join("\n")}
              }
            PROTO
          end

          def proto_zero_value
            @proto_zero_value ||= begin
              factory = schema_def_state.factory # : ::ElasticGraph::SchemaDefinition::Factory & ::ElasticGraph::ProtoIngestion::SchemaDefinition::FactoryExtension
              factory.new_enum_value("UNSPECIFIED", "UNSPECIFIED") do |value|
                value.documentation <<~EOS
                  The default value when no enum value has been explicitly set. Do not use this value.
                  See https://protobuf.dev/programming-guides/proto3/#enum-default.
                EOS
              end
            end
          end

          def proto_zero_value_name
            @proto_zero_value_name ||= "#{proto_enum_value_prefix}_UNSPECIFIED"
          end

          def values_by_proto_name
            @values_by_proto_name ||= {}
          end

          def proto_enum_value_name(value_name)
            if (raw_value = values_by_name[value_name])
              value = raw_value # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumValue & EnumValueExtension
              value.proto_name(proto_enum_value_prefix)
            else
              "#{proto_enum_value_prefix}_#{Support::Casing.to_upper_snake(value_name)}"
            end
          end

          def proto_enum_value_names
            return values_by_name.keys if external_proto_enum_sources.empty?

            values_by_source = external_proto_enum_sources.map { |source| enum_value_names_from_source(source) }
            canonical_values = values_by_source.first
            canonical_set = canonical_values.uniq.sort
            if values_by_source.drop(1).any? { |source_values| source_values.uniq.sort != canonical_set }
              raise Errors::SchemaError, "External proto enums for `#{name}` produce inconsistent value sets. " \
                "Ensure each `external_proto_enum` source (with exclusions/expected_extras/name_transform) resolves to the same values."
            end
            canonical_values
          end

          # Reads the value NAMES a source contributes, applying `name_transform` first and then
          # `exclusions`/`expected_extras` to the transformed names. Contrast with
          # {#enum_value_numbers_from_source}, which reads names AND numbers and applies none of
          # those options -- only external references need numbers, and they forbid the options.
          def enum_value_names_from_source(source)
            name_transform = source.name_transform
            mapped_values = source.proto_enum.enums.map do |entry|
              entry_name = entry.name.to_s
              name_transform ? name_transform.call(entry_name).to_s : entry_name
            end
            (mapped_values - source.exclusions + source.expected_extras).uniq
          rescue => e
            raise Errors::SchemaError, "Failed loading external proto enum values for `#{name}` from `#{source.proto_enum}`: #{e.message}"
          end

          def validate_external_proto_reference(schema)
            unless external_proto_enum_sources.one?
              raise Errors::SchemaError, "External proto enum `#{name}` must use exactly one `external_proto_enum` " \
                "source; multi-source enums cannot be safely referenced externally."
            end

            numbers_by_value_name = enum_value_numbers_from_source(external_proto_enum_sources.first)
            external_names = numbers_by_value_name.keys.sort
            elasticgraph_names = values_by_name.keys.map(&:to_s).uniq.sort
            if external_names != elasticgraph_names
              raise Errors::SchemaError, "External proto enum `#{name}` values do not match the ElasticGraph enum values. " \
                "External values: #{external_names.join(", ")}. ElasticGraph values: #{elasticgraph_names.join(", ")}."
            end

            schema.pinned_enum_value_numbers(name).each do |value_name, pinned_number|
              external_number = numbers_by_value_name[value_name]
              if external_number && external_number != pinned_number
                raise Errors::SchemaError, "External proto enum `#{name}` assigns `#{value_name}` the number " \
                  "#{external_number}, but previously dumped artifacts pin it to #{pinned_number}; referencing it would " \
                  "silently reinterpret existing wire data."
              end

              conflicting_name = numbers_by_value_name.find do |external_name, number|
                external_name != value_name && number == pinned_number
              end&.first
              if conflicting_name
                raise Errors::SchemaError, "External proto enum `#{name}` assigns `#{conflicting_name}` the number " \
                  "#{pinned_number}, which previously dumped artifacts pin to `#{value_name}`; referencing it would " \
                  "silently reinterpret existing wire data."
              end
            end

            # Number 0 belongs to the zero value this gem generates for a local enum, so an
            # external enum that puts a referenced value there could never be generated locally.
            if (zero_value_name = numbers_by_value_name.key(0))
              raise Errors::SchemaError, "External proto enum `#{name}` assigns `#{zero_value_name}` the number 0, " \
                "which is reserved for the generated zero value `#{proto_zero_value_name}`."
            end

            # Record the external numbers so the artifact stays a complete record of the wire
            # format. Without this the enum contributes nothing to `proto_field_numbers.yaml`, and
            # dropping `proto:`/`import:` later would renumber its values from 1.
            schema.pin_enum_value_numbers(name, numbers_by_value_name)
          end

          # Reads the value names AND numbers a source contributes. Contrast with
          # {#enum_value_names_from_source}: this ignores `exclusions`, `expected_extras`, and
          # `name_transform`, which external references forbid, so the names it returns are the
          # proto enum's own.
          def enum_value_numbers_from_source(source)
            entries = read_enum_entries(source)

            # Checked outside `read_enum_entries` so its blanket rescue cannot swallow this and
            # re-raise it as an unexpected-exception failure.
            unless entries.all? { |entry| entry.respond_to?(:number) }
              raise Errors::SchemaError, "External proto enum `#{name}` cannot be referenced: its enum entries " \
                "must expose `.number` so its values can be verified against previously pinned numbers."
            end

            entries.to_h { |entry| [entry.name.to_s, entry.number] }
          end

          def read_enum_entries(source)
            source.proto_enum.enums
          rescue => e
            raise Errors::SchemaError, "Failed loading external proto enum values for `#{name}` from `#{source.proto_enum}`: #{e.message}"
          end
        end
      end
    end
  end
end
