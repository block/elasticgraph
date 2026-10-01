# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/graphql/scalar_coercion_adapters/valid_time_zones"
require "elastic_graph/proto_ingestion/schema_definition/field_number_mappings"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/enum_type_extension"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/object_interface_and_union_extension"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/scalar_type_extension"
require "forwardable"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Builds a `proto2` or `proto3` schema string from an ElasticGraph schema definition.
      class Schema
        extend Forwardable

        # Protobuf syntaxes this generator can emit.
        SUPPORTED_SYNTAXES = %w[proto2 proto3].freeze

        # The protobuf syntax emitted when the schema does not configure one.
        DEFAULT_SYNTAX = "proto3"

        # Field declarations for the indexing event's transport metadata, in allocation order.
        ENVELOPE_METADATA_FIELDS = {
          "op" => "optional string",
          "id" => "optional string",
          "version" => "optional int64",
          "latency_timestamps" => "map<string, google.protobuf.Timestamp>"
        }.freeze

        # Normalizes a configured `syntax` to one of {SUPPORTED_SYNTAXES}.
        #
        # Both the `proto_schema_artifacts` API and this class validate through here so that a
        # syntax is checked exactly once no matter which entry point supplies it.
        #
        # @param syntax [Symbol, String]
        # @return [String]
        def self.validate_syntax(syntax)
          syntax.to_s.tap do |normalized|
            unless SUPPORTED_SYNTAXES.include?(normalized)
              raise Errors::SchemaError, "`syntax` must be one of #{SUPPORTED_SYNTAXES.inspect}, got: #{syntax.inspect}"
            end
          end
        end

        # Validates configured `header_lines`, as {.validate_syntax} does for a syntax.
        #
        # Each element renders as its own line, so a newline in one element would silently produce
        # more lines than the schema asked for.
        #
        # @param header_lines [Array<String>]
        # @return [Array<String>]
        def self.validate_header_lines(header_lines)
          unless header_lines.is_a?(::Array) && header_lines.all?(::String)
            raise Errors::SchemaError, "`header_lines` must be an Array of Strings, got: #{header_lines.inspect}"
          end

          if (multi_line = header_lines.grep(/\n/)).any?
            raise Errors::SchemaError, "`header_lines` must not contain newlines, but got: #{multi_line.inspect}. " \
              "Pass one Array element per line."
          end

          header_lines
        end

        # @param state [ElasticGraph::SchemaDefinition::State]
        # @param all_types [Array<ElasticGraph::SchemaDefinition::SchemaElements::graphQLType>]
        # @param ingestion_state [ProtoIngestionState] this extension's configured schema definition state
        # @param ingestible_types_by_name [Hash<String, Object>] ingestible schema types, including abstract types
        def initialize(
          state:,
          all_types:,
          ingestion_state:,
          ingestible_types_by_name:
        )
          @state = state
          @all_types = all_types
          @ingestible_types_by_name = ingestible_types_by_name
          @package_name = ingestion_state.package_name
          @syntax = self.class.validate_syntax(ingestion_state.syntax)
          @header_lines = self.class.validate_header_lines(ingestion_state.header_lines)
          @field_number_mappings = FieldNumberMappings.from_parsed_yaml(ingestion_state.field_number_mappings)
        end

        # Renders the schema as a valid file in the configured syntax.
        #
        # @return [String]
        def to_proto
          resolve_contracts
          types = proto_types
          return "" if types.empty? && @field_number_mappings.messages.empty?

          validate_unique_enum_value_prefixes(types)

          sections = [
            %(syntax = "#{@syntax}";),
            "package #{@package_name};",
            *render_header_lines,
            *render_imports(types),
            render_definitions(types)
          ]

          sections.join("\n\n") + "\n"
        end

        # Exposes the field-number and enum-value-number mappings for writing to artifact YAML.
        #
        # @return [Hash<String, Object>]
        def field_number_mappings_for_artifact
          @field_number_mappings.to_dumpable_hash
        end

        # Returns the stable protobuf number for a message field.
        #
        # @api private
        def field_number_for(message_name:, type_name:, public_field_name:)
          contract = @field_number_mappings.messages.fetch(type_name).fetch("fields").fetch(public_field_name)
          contract.fetch("field_number")
        end

        # Returns the next available field number for a stable protobuf message name.
        # @api private
        def next_field_number_for(name)
          @field_number_mappings.next_field_number_for(public_type_name(name))
        end

        # Returns retired field numbers for a stable protobuf message name.
        # @api private
        def reserved_field_numbers_for(name, active_names)
          @field_number_mappings.reserved_field_numbers_for(public_type_name(name), active_names)
        end

        # Returns active enum value numbers for a stable protobuf enum name.
        # @api private
        def enum_value_numbers_for(name, active_names)
          values = @field_number_mappings.enums.fetch(public_type_name(name)).fetch("values")
          active_names.to_h { |value| [value, values.fetch(value).fetch("value_number")] }
        end

        # Returns the next available value number for a stable protobuf enum name.
        # @api private
        def next_enum_value_number_for(name)
          @field_number_mappings.next_enum_value_number_for(public_type_name(name))
        end

        # Returns retired value numbers for a stable protobuf enum name.
        # @api private
        def reserved_enum_value_numbers_for(name, active_names)
          @field_number_mappings.reserved_enum_value_numbers_for(public_type_name(name), active_names)
        end

        # Returns the label prefix (including its trailing space) that a field declaration needs
        # under the configured syntax, or an empty string when the field takes no label.
        #
        # Non-repeated fields use `optional` in both syntaxes so that absence is distinct from
        # an explicitly supplied zero, false, or empty string. `oneof` alternatives never
        # get a label under either syntax -- protoc rejects one -- so the `oneof` renderer in
        # `ObjectInterfaceAndUnionExtension` does not call this.
        #
        # @api private
        def field_label_prefix(repeated:)
          return "repeated " if repeated
          "optional "
        end

        # Ingestion facts that the compiled protobuf descriptors cannot express. The indexer reads
        # everything else from the descriptors of the messages it ingests.
        # @return [Hash<String, Object>]
        def ingestion_metadata
          resolve_contracts
          types = proto_types
          metadata = {
            "package_name" => @package_name,
            "fields" => types.filter_map do |type|
              next unless type.respond_to?(:proto_field_overrides)
              overrides = type.proto_field_overrides
              [type.proto_name, overrides] unless overrides.empty?
            end.to_h,
            "enum_values" => types.filter_map do |type|
              next unless type.respond_to?(:proto_enum_value_name_overrides)
              overrides = type.proto_enum_value_name_overrides
              [type.proto_name, overrides] unless overrides.empty?
            end.to_h
          } # : ::Hash[::String, untyped]

          # The indexer can't load GraphQL's time zone list, so it's included when a field needs it.
          if types.any? { |type| type.is_a?(::ElasticGraph::SchemaDefinition::SchemaElements::ScalarType) && type.type_ref.with_reverted_override.name == "TimeZone" }
            metadata["time_zones"] = GraphQL::ScalarCoercionAdapters::VALID_TIME_ZONES.to_a
          end

          metadata["types"] = types.filter_map { |type| [type.proto_name, type.name] if type.respond_to?(:protobuf_contract) && type.proto_name != type.name }.to_h
          metadata["type_aliases"] = retained_type_entries.filter_map do |name, contract|
            next if contract["deleted"]
            aliases = contract.fetch("previous_names", []).to_h { |old| [old, contract.fetch("proto_name", name)] }
            aliases unless aliases.empty?
          end.reduce({}, :merge)
          metadata["retired_enum_values"] = @field_number_mappings.enums.filter_map do |name, contract|
            numbers = contract.fetch("values").values.filter_map { |value| value.fetch("value_number") if value["deleted"] }
            [contract.fetch("proto_name", name), numbers] unless numbers.empty?
          end.to_h
          metadata["deleted_types"] = retained_type_entries.flat_map do |name, contract|
            contract["deleted"] ? [name, contract.fetch("proto_name", name), *contract.fetch("previous_names", [])] : []
          end.uniq.sort
          envelope = @field_number_mappings.messages["ElasticGraphEventEnvelope"]
          metadata["reserved_envelope_fields"] = envelope ? envelope.fetch("fields").filter_map do |name, field|
            next unless field["deleted"]
            proto_type = field["proto_type"].to_s.delete_prefix(".").delete_prefix("#{@package_name}.")
            [field.fetch("field_number").to_s, proto_type] if metadata["deleted_types"].include?(proto_type)
          end.to_h : {}
          metadata.reject { |_, value| value.respond_to?(:empty?) && value.empty? }
        end

        private

        def retained_type_entries
          @field_number_mappings.messages.merge(@field_number_mappings.enums).except("ElasticGraphEventEnvelope")
        end

        def public_type_name(proto_name)
          retained_type_entries.find { |name, contract| contract.fetch("proto_name", name) == proto_name }&.first || proto_name
        end

        # Resolve identities first, then field contracts. This makes rendering and runtime overrides
        # consume the same effective contract regardless of which artifact is requested first.
        def resolve_contracts
          return if @contracts_resolved
          types = proto_types
          retained_names = retained_type_entries.flat_map { |name, contract| [name, *contract.fetch("previous_names", [])] }
          # @type var contract_types: ::Array[untyped]
          contract_types = @all_types.select do |type|
            previous_names = @state.renamed_types_by_old_name.filter_map { |old, current| old if current.name == type.name }
            types.include?(type) || retained_names.include?(type.name) || (previous_names & retained_names).any?
          end
          contract_types.each do |type|
            next unless type.respond_to?(:protobuf_contract=)
            section = type.is_a?(::ElasticGraph::SchemaDefinition::SchemaElements::EnumType) ? "enums" : "messages"
            previous_names = @state.renamed_types_by_old_name.filter_map { |old, current| old if current.name == type.name }
            contract = @field_number_mappings.type_contract_for(section: section, public_name: type.name, previous_names: previous_names)
            type.protobuf_contract = contract
          end
          @field_number_mappings.retire_types(@all_types.map(&:name), @state.deleted_types_by_old_name.keys)
          contract_types.each do |raw_type|
            if raw_type.is_a?(::ElasticGraph::SchemaDefinition::SchemaElements::EnumType)
              type = raw_type # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumType & SchemaElements::EnumTypeExtension
              enum_contract = type.protobuf_contract # : FieldNumberMappings::contract
              enum_contract.fetch("values").each do |old_name, value_contract|
                value_contract["proto_name"] ||= "#{type.proto_enum_value_prefix}_#{Support::Casing.to_upper_snake(old_name)}"
              end
              type.values_by_name.each_value do |raw_value|
                value = raw_value # : ::ElasticGraph::SchemaDefinition::SchemaElements::EnumValue & SchemaElements::EnumValueExtension
                value.protobuf_contract = @field_number_mappings.enum_value_contract_for(
                  enum_name: type.name, public_name: value.name,
                  proto_name: value.proto_name(type.proto_enum_value_prefix), previous_names: value.protobuf_previous_names
                )
              end
              @field_number_mappings.retire_enum_values(type.name, type.values_by_name.keys)
            elsif raw_type.respond_to?(:protobuf_contract)
              resolve_message_fields(raw_type)
            end
          end
          envelope_fields = ENVELOPE_METADATA_FIELDS.merge(envelope_record_fields)
          unless types.empty? && @field_number_mappings.messages.empty?
            envelope_fields.each do |name, declaration|
              depth = declaration.start_with?("map<") ? 1 : 0
              proto_type = declaration.delete_prefix("optional ")
              @field_number_mappings.field_contract_for(message_name: "ElasticGraphEventEnvelope", public_field_name: name, proto_type: proto_type, list_depth: depth)
            end
          end
          @field_number_mappings.retire_fields("ElasticGraphEventEnvelope", envelope_fields.keys, synthetic: true) unless @field_number_mappings.messages.empty?
          @field_number_mappings.warnings.each { |warning| @state.output.puts(warning) }
          @contracts_resolved = true
        end

        def resolve_message_fields(type)
          if type.abstract?
            active_names = type.recursively_resolve_subtypes.map do |subtype|
              name = Support::Casing.to_upper_snake(subtype.proto_name).downcase
              @field_number_mappings.field_contract_for(message_name: type.name, public_field_name: name, proto_type: subtype.proto_type_reference(@package_name))
              name
            end
            @field_number_mappings.retire_fields(type.name, active_names, synthetic: true)
          else
            fields = type.proto_fields
            fields.each do |schema_field, field|
              depth, base = SchemaElements::ObjectInterfaceAndUnionExtension.list_depth_and_base_type(field.type)
              proto_base = base.resolved # : untyped
              schema_field.protobuf_contract = @field_number_mappings.field_contract_for(
                message_name: type.name, public_field_name: schema_field.name,
                previous_field_names: previous_field_names_for(type.name, schema_field.name),
                proto_type: proto_base.proto_type_reference(@package_name), list_depth: depth,
                proto_name: schema_field.protobuf_name
              )
            end
            deleted_names = @state.deleted_fields_by_type_name_and_old_field_name[type.name].keys
            @field_number_mappings.retire_fields(type.name, fields.map { |field, _| field.name }, deleted_names: deleted_names)
          end
        end

        def envelope_definitions
          record_fields = envelope_record_fields
          active_names = ENVELOPE_METADATA_FIELDS.keys + record_fields.keys
          metadata = render_envelope_fields(ENVELOPE_METADATA_FIELDS, indent: "  ")
          alternatives = render_envelope_fields(record_fields, indent: "    ")
          reserved = render_reserved_envelope_fields(active_names)

          record = alternatives.empty? ? "" : "  oneof record {\n#{alternatives}\n  }"
          body_sections = [metadata, record, reserved].reject(&:empty?)
          envelope = <<~PROTO
            message ElasticGraphEventEnvelope {
            #{body_sections.join("\n\n")}
            }
          PROTO

          batch = <<~PROTO
            message ElasticGraphEventBatch {
              repeated ElasticGraphEventEnvelope events = 1;
            }
          PROTO

          {"ElasticGraphEventEnvelope" => envelope.strip, "ElasticGraphEventBatch" => batch.strip}
        end

        def envelope_record_fields
          type_names_by_field_name = {} # : ::Hash[::String, ::String]

          @ingestible_types_by_name.values.sort_by(&:name).to_h do |type|
            # @type var proto_type: SchemaElements::ObjectInterfaceAndUnionExtension
            proto_type = _ = type
            field_name = Support::Casing.to_upper_snake(proto_type.proto_name).downcase
            if ENVELOPE_METADATA_FIELDS.key?(field_name) || field_name == "record"
              raise Errors::SchemaError, "Ingestible type `#{type.name}` maps to reserved protobuf envelope field `#{field_name}`. " \
                "Rename `#{type.name}` so its snake_case name does not conflict with a reserved envelope field."
            end
            if (existing_type_name = type_names_by_field_name[field_name])
              raise Errors::SchemaError, "Ingestible types `#{existing_type_name}` and `#{type.name}` map to " \
                "the same protobuf envelope field `#{field_name}`. " \
                "Rename one of these types so their names remain distinct when converted to snake_case."
            end

            type_names_by_field_name[field_name] = type.name
            [field_name, proto_type.proto_type_reference(@package_name)]
          end
        end

        def render_envelope_fields(fields, indent:)
          fields.map do |name, declaration|
            number = field_number_for(
              message_name: "ElasticGraphEventEnvelope",
              type_name: "ElasticGraphEventEnvelope",
              public_field_name: name
            )
            [number, "#{indent}#{declaration} #{name} = #{number};"]
          end.sort_by(&:first).map(&:last).join("\n")
        end

        def render_reserved_envelope_fields(active_names)
          reserved_field_numbers_for("ElasticGraphEventEnvelope", active_names).map do |name, number|
            "  reserved #{number}; // Previously used by #{name}."
          end.join("\n")
        end

        # Selects the ingestible types and every type transitively referenced by their protobuf
        # representations. All traversal state is local so repeated calls are independent.
        def proto_types
          # Types gain proto methods through instance extensions that Steep cannot see.
          # @type var types_to_visit: ::Array[untyped]
          types_to_visit = @ingestible_types_by_name.values
          type_names_to_render = ::Set.new

          while (type = types_to_visit.shift)
            next unless type_names_to_render.add?(type.name)

            types_to_visit.concat(type.referenced_proto_types)
          end

          @all_types.select do |type|
            type_names_to_render.include?(type.name)
          end
        end

        def render_definitions(types)
          definitions = types.to_h { |type| [type.proto_name, type.to_proto(self, @package_name)] }
          definitions.merge(envelope_definitions).compact.sort.map(&:last).join("\n\n")
        end

        # Every type reports the proto file it needs imported, or `nil` when it needs none. Today only
        # scalar types map to an externally defined proto type, but enum and object types can start
        # requiring an import without any change here.
        def render_imports(types)
          imports = (types.filter_map(&:protobuf_import) + ["google/protobuf/timestamp.proto"]).uniq.sort

          [imports.map { |import| %(import "#{import}";) }.join("\n")]
        end

        def render_header_lines
          @header_lines.empty? ? [] : [@header_lines.join("\n")]
        end

        def validate_unique_enum_value_prefixes(types)
          enum_type_by_prefix = {} # : ::Hash[::String, untyped]

          types.grep(SchemaElements::EnumTypeExtension).each do |type|
            if (existing_enum_type = enum_type_by_prefix[type.proto_enum_value_prefix])
              raise Errors::SchemaError, "Enum types `#{existing_enum_type.name}` and `#{type.name}` map to " \
                "duplicate protobuf enum value prefix `#{type.proto_enum_value_prefix}`."
            end

            enum_type_by_prefix[type.proto_enum_value_prefix] = type
          end
        end

        def previous_field_names_for(type_name, public_field_name)
          previous_field_names_by_type_name_and_field_name.dig(type_name, public_field_name) || []
        end

        # Inverts the state's `old_field_name => renamed_field` index into the form we need here:
        # the old public names a field's current public name was renamed from.
        def previous_field_names_by_type_name_and_field_name
          @previous_field_names_by_type_name_and_field_name ||= @state.renamed_fields_by_type_name_and_old_field_name.transform_values do |old_to_new|
            old_to_new
              .group_by { |_, renamed_field| renamed_field.name }
              .transform_values { |renames| renames.map(&:first) }
          end
        end
      end
    end
  end
end
