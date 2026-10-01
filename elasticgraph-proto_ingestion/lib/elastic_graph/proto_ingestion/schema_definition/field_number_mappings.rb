# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/support/from_yaml_file"
require "elastic_graph/support/json_schema/validator_factory"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Durable protobuf identities and wire contracts. Unlike regenerated descriptors, this
      # registry retains deleted fields, rotated incarnations, and historical public names.
      class FieldNumberMappings
        extend Support::FromYamlFile

        # The largest field number protobuf permits.
        MAX_FIELD_NUMBER = 536_870_911
        # Numbers reserved for the protobuf implementation.
        RESERVED_FIELD_NUMBER_RANGE = 19_000..19_999
        # The largest positive enum value number protobuf permits.
        MAX_ENUM_VALUE_NUMBER = 2_147_483_647
        # Directional widenings which preserve every value written by an older publisher.
        INTEGER_WIDENINGS = {"int32" => "int64", "sint32" => "sint64", "uint32" => "uint64"}.freeze

        field_number_schema = {
          "type" => "integer", "minimum" => 1, "maximum" => MAX_FIELD_NUMBER,
          "not" => {"minimum" => RESERVED_FIELD_NUMBER_RANGE.begin, "maximum" => RESERVED_FIELD_NUMBER_RANGE.end}
        }
        enum_number_schema = {"type" => "integer", "minimum" => 1, "maximum" => MAX_ENUM_VALUE_NUMBER}
        names_schema = {"type" => "array", "items" => {"type" => "string"}, "uniqueItems" => true}
        identity_properties = {
          "proto_name" => {"type" => "string"}, "previous_names" => names_schema,
          "previous_proto_names" => names_schema, "deleted" => {"const" => true}
        }
        field_contract_schema = {
          "type" => "object",
          "properties" => identity_properties.merge(
            "field_number" => field_number_schema,
            "proto_type" => {"type" => "string"},
            "list_depth" => {"type" => "integer", "minimum" => 0}
          ),
          "required" => ["field_number"], "additionalProperties" => false
        }
        value_contract_schema = {
          "type" => "object",
          "properties" => identity_properties.merge("value_number" => enum_number_schema),
          "required" => ["value_number"], "additionalProperties" => false
        }

        # Validated input format; integers are accepted only to migrate older number-only files.
        JSON_SCHEMA = {
          "$schema" => "http://json-schema.org/draft-07/schema#", "type" => "object",
          "properties" => {
            "messages" => {"type" => "object", "additionalProperties" => {
              "type" => "object", "properties" => identity_properties.merge(
                "fields" => {"type" => "object", "additionalProperties" => {"anyOf" => [field_number_schema, field_contract_schema]}},
                "retired_fields" => {"type" => "object", "additionalProperties" => field_contract_schema},
                "next_number" => field_number_schema.merge("maximum" => MAX_FIELD_NUMBER + 1)
              ), "required" => ["fields", "next_number"], "additionalProperties" => false
            }},
            "enums" => {"type" => "object", "additionalProperties" => {
              "type" => "object", "properties" => identity_properties.merge(
                "values" => {"type" => "object", "additionalProperties" => {"anyOf" => [enum_number_schema, value_contract_schema]}},
                "next_number" => enum_number_schema.merge("maximum" => MAX_ENUM_VALUE_NUMBER + 1)
              ), "required" => ["values", "next_number"], "additionalProperties" => false
            }}
          }, "additionalProperties" => false
        }
        VALIDATOR = Support::JSONSchema::Validator.new(
          schema: Support::JSONSchema::ValidatorFactory.new(schema: JSON_SCHEMA, sanitize_pii: false).root_schema,
          sanitize_pii: false
        )
        private_constant :VALIDATOR

        # Builds and validates a registry from its YAML representation.
        # @param parsed_yaml [Hash, nil]
        # @return [FieldNumberMappings]
        def self.from_parsed_yaml(parsed_yaml)
          parsed_yaml ||= {} # : ::Hash[::String, untyped]
          if (error = VALIDATOR.validate_with_error_message(parsed_yaml))
            raise Errors::SchemaError, "Invalid protobuf field-number mappings:\n\n#{error}"
          end
          new(parsed_yaml)
        end

        # @param parsed_yaml [Hash] validated registry input
        # @api private
        def initialize(parsed_yaml)
          empty_contracts = {} # : contracts
          @mappings = Marshal.load(Marshal.dump(parsed_yaml))
          @mappings["messages"] ||= {}
          @mappings["enums"] ||= {}
          @mappings.each do |section, entries|
            entries.each do |name, entry|
              members_key, number_key = (section == "messages") ? ["fields", "field_number"] : ["values", "value_number"]
              entry[members_key].transform_values! { |value| value.is_a?(Integer) ? {number_key => value} : value }
              all_members = entry[members_key].to_a + entry.fetch("retired_fields", empty_contracts).to_a
              numbers = all_members.each_with_index.to_h { |(member, value), index| ["#{member}:#{index}", value.fetch(number_key)] }
              verify_numbers(name, entry.fetch("next_number"), numbers, section)
              verify_names(name, entry[members_key])
              verify_wire_names(name, all_members) if section == "messages"
            end
            verify_names(section, entries)
          end
          @warnings = []
        end

        # Source-breaking changes encountered while reconciling the current contract.
        # @return [Array<String>]
        # @dynamic warnings
        attr_reader :warnings

        # Resolves a durable message or enum identity before any references are rendered.
        # @return [Hash<String, Object>] its retained contract
        def type_contract_for(section:, public_name:, previous_names: [])
          empty_contracts = {} # : contracts
          entries = @mappings.fetch(section)
          other_entries = @mappings.fetch((section == "messages") ? "enums" : "messages")
          if other_entries.any? { |name, contract| (identity_names(name, contract) & [public_name, *previous_names]).any? }
            raise Errors::SchemaError, "Cannot change protobuf type `#{public_name}` between a message and an enum. Choose a fresh type name and rotate referencing fields."
          end
          entry = migrate_identity(entries, public_name, previous_names, "protobuf type")
          unless entry
            collision = entries.find { |name, stored| identity_names(name, stored).include?(public_name) }
            if collision
              raise Errors::SchemaError, "Protobuf type name `#{public_name}` is already retained by `#{collision.first}`. Choose a different public name."
            end
            key = (section == "messages") ? "fields" : "values"
            entry = {key => empty_contracts, "next_number" => 1}
            entries[public_name] = entry
          end
          entry.delete("deleted")
          entry
        end

        # Resolves a field's number, name, and effective retained wire type.
        # An incompatible change must explicitly choose a fresh protobuf name.
        # @return [Hash<String, Object>]
        def field_contract_for(message_name:, public_field_name:, proto_type:, previous_field_names: [], list_depth: 0, proto_name: nil)
          empty_contracts = {} # : contracts
          empty_names = [] # : ::Array[::String]
          mapping = message_mapping_for(message_name)
          fields = mapping.fetch("fields")
          contract = migrate_identity(fields, public_field_name, previous_field_names, "protobuf field in `#{message_name}`")
          unless contract
            collision = fields.find do |name, stored|
              identity_names(name, stored).include?(public_field_name) || mapping.fetch("retired_fields", empty_contracts).any? do |_, retired|
                aliases = retired.fetch("previous_names", empty_names)
                aliases.include?(name) && aliases.include?(public_field_name)
              end
            end
            if collision
              raise Errors::SchemaError, "Protobuf public field name `#{public_field_name}` is already retained by field `#{collision.first}`. Choose a different public name or declare `renamed_from` for the original identity."
            end
          end
          wire_name = proto_name || contract&.fetch("proto_name", public_field_name) || public_field_name
          if (retired = mapping.fetch("retired_fields", empty_contracts)[wire_name])
            public_names = [public_field_name, *contract&.fetch("previous_names", empty_names)]
            same_identity = (retired.fetch("previous_names", empty_names) & public_names).any?
            unless same_identity && compatible_type(retired["proto_type"], proto_type, retired.fetch("list_depth", 0), list_depth)
              raise Errors::SchemaError, "Protobuf name `#{wire_name}` is retired with a different wire contract. Choose a fresh `protobuf name:`."
            end
            mapping.fetch("retired_fields").delete(wire_name)
            if contract
              old_wire = contract.fetch("proto_name", public_field_name)
              mapping["retired_fields"][old_wire] = contract.merge("proto_name" => old_wire, "previous_names" => (contract.fetch("previous_names", empty_names) + [public_field_name]).uniq, "deleted" => true)
            end
            contract = retired
            fields[public_field_name] = contract
          end
          if contract
            old_wire_name = contract.fetch("proto_name", public_field_name)
            if contract["deleted"] && !contract["proto_type"]
              raise Errors::SchemaError, "Cannot restore `#{message_name}.#{public_field_name}`: its legacy mapping has no historical proto_type. Record the original wire contract before restoring it."
            end
            compatible = compatible_type(contract["proto_type"], proto_type, contract.fetch("list_depth", 0), list_depth)
            if compatible
              if wire_name != old_wire_name
                ensure_wire_name_available(mapping, wire_name, except: contract)
                contract["previous_proto_names"] = (contract.fetch("previous_proto_names", empty_names) + [old_wire_name]).uniq
                @warnings << "Source-breaking protobuf rename: `#{message_name}.#{old_wire_name}` becomes `#{wire_name}`; its number is unchanged."
              end
              if contract["proto_type"] && compatible != contract["proto_type"]
                @warnings << "Source-breaking protobuf widening: `#{message_name}.#{wire_name}` changes from #{contract["proto_type"]} to #{compatible}. Upgrade downstream readers before publishing values outside the old range."
              end
              if contract["proto_type"].nil? && !@warnings.any? { |warning| warning.start_with?("Migrating legacy") }
                @warnings << "Migrating legacy protobuf field-number mappings using the current schema. Dump the unchanged schema before evolving it; absent fields retain unknown historical contracts."
              end
              contract["proto_type"] = compatible
              contract["list_depth"] = list_depth
              contract.delete("deleted")
            elsif wire_name != old_wire_name
              ensure_wire_name_available(mapping, wire_name)
              mapping["retired_fields"] ||= {}
              mapping["retired_fields"][old_wire_name] = contract.merge("proto_name" => old_wire_name, "previous_names" => (contract.fetch("previous_names", empty_names) + [public_field_name]).uniq, "deleted" => true)
              contract = allocate_field_contract(message_name, mapping, proto_type, list_depth)
              fields[public_field_name] = contract
            else
              raise Errors::SchemaError, "Incompatible protobuf change for `#{message_name}.#{public_field_name}`: #{contract["proto_type"]} (list depth #{contract.fetch("list_depth", 0)}) cannot carry #{proto_type} (list depth #{list_depth}). Use `f.protobuf name: \"#{wire_name}_new\"` to rotate to a fresh number."
            end
          else
            ensure_wire_name_available(mapping, wire_name)
            contract = allocate_field_contract(message_name, mapping, proto_type, list_depth)
            fields[public_field_name] = contract
          end
          (wire_name == public_field_name) ? contract.delete("proto_name") : contract["proto_name"] = wire_name
          contract
        end

        # Marks absent fields as deleted, requiring an explicit declaration for user fields.
        # Synthetic oneof alternatives are retired automatically when membership changes.
        # @return [void]
        def retire_fields(message_name, active_names, deleted_names: [], synthetic: false)
          message_mapping_for(message_name).fetch("fields").each do |name, contract|
            next if active_names.include?(name) || contract["deleted"]
            unless synthetic || deleted_names.any? { |deleted| identity_names(name, contract).include?(deleted) }
              raise Errors::SchemaError, "The `#{message_name}.#{name}` field no longer exists in the current schema definition. Declare `deleted_field \"#{name}\"` or `renamed_from`."
            end
            contract["deleted"] = true
          end
        end

        # Requires explicit deletion only when a retained user type actually disappears from the
        # schema definition, not merely from the ingestible/reachable set.
        # @return [void]
        def retire_types(defined_names, deleted_names)
          @mappings.each_value do |entries|
            entries.each do |name, contract|
              next if name == "ElasticGraphEventEnvelope" || defined_names.include?(name) || contract["deleted"]
              unless deleted_names.any? { |deleted| identity_names(name, contract).include?(deleted) }
                raise Errors::SchemaError, "The `#{name}` type no longer exists in the current schema definition. Declare `deleted_type \"#{name}\"` or `renamed_from`."
              end
              contract["deleted"] = true
            end
          end
        end

        # Resolves enum value identities, retaining their generated source names across renames.
        # @return [Hash<String, Object>]
        def enum_value_contract_for(enum_name:, public_name:, proto_name:, previous_names: [])
          mapping = enum_mapping_for(enum_name)
          values = mapping.fetch("values")
          contract = migrate_identity(values, public_name, previous_names, "protobuf enum value")
          unless contract
            ensure_value_name_available(values, public_name, proto_name)
            number = mapping.fetch("next_number")
            if number > MAX_ENUM_VALUE_NUMBER
              raise Errors::SchemaError, "Cannot allocate another protobuf enum value number for enum `#{enum_name}`: the maximum enum value number (#{MAX_ENUM_VALUE_NUMBER}) has been reached."
            end
            contract = {"value_number" => number}
            values[public_name] = contract
            mapping["next_number"] = number + 1
          end
          contract["proto_name"] ||= proto_name
          contract.delete("deleted")
          contract
        end

        # Retains enum values removed from the current enum.
        # @return [void]
        def retire_enum_values(enum_name, active_names)
          enum_mapping_for(enum_name).fetch("values").each do |name, contract|
            contract["deleted"] = true unless active_names.include?(name)
          end
        end

        # Returns all stored message contracts, including tombstones.
        # @return [Hash<String, Object>]
        def messages = @mappings.fetch("messages")

        # Returns all stored enum contracts, including tombstones.
        # @return [Hash<String, Object>]
        def enums = @mappings.fetch("enums")

        # Returns the allocation cursor for a message.
        # @return [Integer]
        def next_field_number_for(message_name) = message_mapping_for(message_name).fetch("next_number")

        # Returns the allocation cursor for an enum.
        # @return [Integer]
        def next_enum_value_number_for(enum_name) = enum_mapping_for(enum_name).fetch("next_number")

        # Returns absent or rotated field numbers keyed by their retained protobuf names.
        # @return [Hash<String, Integer>]
        def reserved_field_numbers_for(message_name, active_field_names)
          empty_contracts = {} # : contracts
          mapping = message_mapping_for(message_name)
          active_fields = mapping.fetch("fields") # : contracts
          fields = active_fields.except(*active_field_names).to_a + mapping.fetch("retired_fields", empty_contracts).to_a
          fields.to_h do |name, contract|
            [contract.fetch("proto_name", name), contract.fetch("field_number")]
          end.sort_by(&:last).to_h
        end

        # Returns removed enum numbers keyed by their prior public names.
        # @return [Hash<String, Integer>]
        def reserved_enum_value_numbers_for(enum_name, active_names)
          values = enum_mapping_for(enum_name).fetch("values") # : contracts
          values.except(*active_names)
            .transform_values { |contract| contract.fetch("value_number") }.sort_by(&:last).to_h
        end

        # Serializes every retained identity and contract, sorted deterministically.
        # @return [Hash<String, Object>]
        def to_dumpable_hash # : contracts
          @mappings.to_h do |section, entries|
            [section, entries.sort.to_h do |name, entry|
              members_key, number_key = (section == "messages") ? ["fields", "field_number"] : ["values", "value_number"]
              sorted = entry.merge(members_key => entry.fetch(members_key).sort_by { |member, contract| [contract.fetch(number_key), member] }.to_h)
              if entry["retired_fields"]
                sorted["retired_fields"] = entry.fetch("retired_fields").sort_by { |member, contract| [contract.fetch(number_key), member] }.to_h
              end
              [name, sorted]
            end]
          end
        end

        private

        def message_mapping_for(name)
          @mappings.fetch("messages")[name] ||= {"fields" => {}, "next_number" => 1}
        end

        def enum_mapping_for(name)
          @mappings.fetch("enums")[name] ||= {"values" => {}, "next_number" => 1}
        end

        def migrate_identity(entries, name, previous_names, description)
          matches = entries.select { |old_name, contract| previous_names.any? { |previous| identity_names(old_name, contract).include?(previous) } }
          if matches.size > 1 || (entries.key?(name) && matches.keys.any? { |old| old != name })
            raise Errors::SchemaError, "Cannot preserve a #{description} identity for `#{name}`: multiple previous names have mappings (#{matches.keys.sort.join(", ")}). Use `renamed_from` for only the original identity."
          end
          return entries[name] if entries.key?(name)
          old_name, contract = matches.first
          return nil unless contract
          entries.delete(old_name)
          contract["proto_name"] ||= old_name
          contract["previous_names"] = (contract.fetch("previous_names", []) + [old_name]).uniq
          entries[name] = contract
        end

        def identity_names(name, contract)
          [name, contract.fetch("proto_name", name), *contract.fetch("previous_names", []), *contract.fetch("previous_proto_names", [])]
        end

        def compatible_type(old, desired, old_depth, depth)
          return desired if old.nil?
          return nil unless old_depth == depth
          return desired if old == desired || INTEGER_WIDENINGS[old] == desired
          return old if INTEGER_WIDENINGS[desired] == old
          nil
        end

        def ensure_wire_name_available(mapping, wire_name, except: nil)
          empty_names = [] # : ::Array[::String]
          empty_contracts = {} # : contracts
          members = mapping.fetch("fields").to_a + mapping.fetch("retired_fields", empty_contracts).to_a
          collision = members.find do |name, contract|
            !contract.equal?(except) && [contract.fetch("proto_name", name), *contract.fetch("previous_proto_names", empty_names)].include?(wire_name)
          end
          return unless collision
          raise Errors::SchemaError, "Protobuf name `#{wire_name}` is already retained by field `#{collision.first}`. Choose a different `protobuf name:` or restore the original field with its original wire contract."
        end

        def ensure_value_name_available(values, public_name, proto_name)
          collision = values.find { |name, contract| (identity_names(name, contract) & [public_name, proto_name]).any? }
          return unless collision
          raise Errors::SchemaError, "Protobuf enum value name `#{proto_name}` is already retained by `#{collision.first}`. Restore the original value or use a different name."
        end

        def allocate_field_contract(message_name, mapping, proto_type, list_depth)
          number = mapping.fetch("next_number")
          if number > MAX_FIELD_NUMBER
            raise Errors::SchemaError, "Cannot allocate another protobuf field number for message `#{message_name}`: the maximum field number (#{MAX_FIELD_NUMBER}) has been reached."
          end
          next_number = number + 1
          next_number = RESERVED_FIELD_NUMBER_RANGE.end + 1 if RESERVED_FIELD_NUMBER_RANGE.cover?(next_number)
          mapping["next_number"] = next_number
          {"field_number" => number, "proto_type" => proto_type, "list_depth" => list_depth}
        end

        def verify_numbers(name, next_number, numbers, section)
          numbers.group_by(&:last).each_value do |entries|
            next if entries.size < 2
            kind = (section == "messages") ? "field-number mapping collision in message" : "enum value-number mapping collision in enum"
            names = entries.map { |member, _| "`#{member.split(":").first}`" }.sort.join(" and ")
            raise Errors::SchemaError, "Protobuf #{kind} `#{name}`: #{names} are both mapped to number #{entries.first.last}."
          end
          maximum = numbers.values.max
          if maximum && next_number <= maximum
            raise Errors::SchemaError, "Protobuf `next_number` for #{(section == "messages") ? "message" : "enum"} `#{name}` must be greater than every mapped number (maximum: #{maximum}), got: #{next_number}."
          end
        end

        def verify_wire_names(description, entries)
          empty_names = [] # : ::Array[::String]
          owner_by_name = {} # : ::Hash[::String, ::Integer]
          entries.each do |name, contract|
            [contract.fetch("proto_name", name), *contract.fetch("previous_proto_names", empty_names)].uniq.each do |wire_name|
              number = contract.fetch("field_number")
              if (owner = owner_by_name[wire_name]) && owner != number
                raise Errors::SchemaError, "Protobuf name collision in #{description}: `#{wire_name}` is retained by both numbers #{owner} and #{number}."
              end
              owner_by_name[wire_name] = number
            end
          end
        end

        def verify_names(description, entries)
          owner_by_name = {} # : ::Hash[::String, ::String]
          entries.each do |name, contract|
            identity_names(name, contract).uniq.each do |alias_name|
              if (owner = owner_by_name[alias_name]) && owner != name
                raise Errors::SchemaError, "Protobuf name collision in #{description}: `#{alias_name}` is retained by both `#{owner}` and `#{name}`."
              end
              owner_by_name[alias_name] = name
            end
          end
        end
      end
    end
  end
end
