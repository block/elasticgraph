# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Reads wire contracts from ElasticGraph's generated protobuf declarations and retains
      # removed fields in comments so their contracts survive later dumps and restoration.
      # This reads the generator's output format, rather than arbitrary hand-written protobuf.
      #
      # @private
      class WireContracts
        Contract = ::Data.define(:field_name, :proto_type, :list_depth)
        private_constant :Contract

        # @param previous_proto [String, nil] previously dumped schema.proto contents
        # @param package_name [String] package of the proposed schema
        def initialize(previous_proto, package_name)
          @contracts = {} # : ::Hash[[::String, ::Integer], Contract]
          @active_keys = ::Set.new # : ::Set[[::String, ::Integer]]
          read_contracts(previous_proto, package_name) if previous_proto
        end

        # Checks a field against the previous declaration assigned to its number, then records
        # its new public name. Renames therefore keep the original wire contract.
        #
        # @param message_name [String]
        # @param field_name [String]
        # @param number [Integer]
        # @param proto_type [String] base type beneath nested-list wrappers
        # @param list_depth [Integer]
        # @return [void]
        def verify_and_record(message_name, field_name, number, proto_type, list_depth)
          key = [message_name, number] # : [::String, ::Integer]
          if (old = @contracts[key]) && (old.proto_type != proto_type || old.list_depth != list_depth)
            raise Errors::SchemaError, "Incompatible protobuf change for `#{message_name}.#{field_name}`: " \
              "retained #{old.proto_type} (list depth #{old.list_depth}), requested #{proto_type} (list depth #{list_depth}). " \
              "Use a new field name to assign a fresh protobuf number."
          end

          @contracts[key] = Contract.new(field_name: field_name, proto_type: proto_type, list_depth: list_depth)
          @active_keys.add(key)
          nil
        end

        # Renders contracts whose declarations are absent, including fields of removed messages.
        # Active fields carry their contract in the actual protobuf declaration instead.
        #
        # @return [String]
        def retired_contract_comments
          @contracts.sort.filter_map do |(message_name, number), contract|
            next if @active_keys.include?([message_name, number])

            "// Retained wire contract: #{message_name}.#{contract.field_name} = #{number}; " \
              "#{contract.proto_type} (list depth #{contract.list_depth})."
          end.join("\n")
        end

        private

        def read_contracts(proto, package_name)
          old_package = proto[/^package ([\w.]+);$/, 1] || package_name
          messages = {} # : ::Hash[::String, ::Hash[::Integer, [::String, ::String, ::Integer]]]
          scopes = [] # : ::Array[[::String, ::String]]

          proto.each_line do |line|
            if (retired = line.match(%r{^// Retained wire contract: (\w+)\.(\w+) = (\d+); (.+) \(list depth (\d+)\)\.$}))
              @contracts[[retired[1], retired[3].to_i]] = Contract.new(
                field_name: retired[2], proto_type: retired[4], list_depth: retired[5].to_i
              )
            end

            declaration = line.sub(%r{//.*}, "").strip
            if (opening = declaration.match(/\A(message|enum|oneof) (\w+) \{\z/))
              scopes << [opening[1], opening[2]]
            elsif declaration == "}"
              scopes.pop
            elsif scopes.any? && scopes.none? { |kind, _| kind == "enum" }
              field = declaration.match(/\A(?:(optional|repeated) )?([\w.]+|map<.+>) (\w+) = (\d+);\z/)
              next unless field

              message_name = scopes.filter_map { |kind, name| name if kind == "message" }.join(".")
              fields = messages[message_name] ||= {}
              depth = (field[1] == "repeated" || field[2].start_with?("map<")) ? 1 : 0
              fields[field[4].to_i] = [field[3], field[2], depth]
            end
          end

          messages.each do |message_name, fields|
            next if message_name.include?(".") # Nested messages are generated list wrappers.

            fields.each do |number, (field_name, proto_type, depth)|
              while depth > 0 && proto_type.start_with?(".#{old_package}.#{message_name}.")
                wrapper = messages.fetch(proto_type.delete_prefix(".#{old_package}."))
                _, proto_type, inner_depth = wrapper.fetch(1)
                depth += inner_depth
              end
              @contracts[[message_name, number]] = Contract.new(field_name: field_name, proto_type: proto_type, list_depth: depth)
            end
          end
        end
      end
    end
  end
end
