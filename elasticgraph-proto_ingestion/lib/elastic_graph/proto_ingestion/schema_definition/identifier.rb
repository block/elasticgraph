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
      # Helpers for rendering Protocol Buffers identifiers while avoiding keyword conflicts.
      class Identifier
        # Matches a single valid protobuf identifier (e.g. one segment of a package name).
        # https://protobuf.com/docs/language-spec#identifiers-and-keywords
        VALID_IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/

        # @dynamic self.enum_name, self.field_name, self.enum_value_name

        class << self
          # Validates a protobuf package identifier.
          #
          # @param name [#to_s]
          # @return [String]
          def validate_package_name(name)
            name = name.to_s
            segments = name.split(".", -1)

            if segments.empty? || segments.any? { |segment| !VALID_IDENTIFIER.match?(segment) }
              raise Errors::SchemaError, "`package_name` must be a dot-separated list of protobuf identifiers " \
                "(each starting with a letter or underscore, containing only letters, digits, and underscores), " \
                "got: #{name.inspect}."
            end

            name
          end

          # Builds a protobuf message identifier.
          #
          # @param name [#to_s]
          # @return [String]
          def message_name(name)
            escape_keyword(name.to_s)
          end

          # Builds a protobuf enum identifier.
          #
          # @return [String]
          alias_method :enum_name, :message_name

          # Builds a protobuf field identifier.
          #
          # @return [String]
          alias_method :field_name, :message_name

          # Builds a protobuf enum value identifier.
          #
          # @return [String]
          alias_method :enum_value_name, :message_name

          # Escapes protobuf reserved keywords by suffixing them with an underscore.
          #
          # @param identifier [String]
          # @return [String]
          private

          def escape_keyword(identifier)
            return identifier unless PROTO_KEYWORDS.include?(identifier)
            "#{identifier}_"
          end
        end

        # Reserved words in protobuf syntax that cannot be used as identifiers verbatim.
        #
        # @return [Set<String>]
        PROTO_KEYWORDS = ::Set[
          "bool", "bytes", "double", "enum", "false", "fixed32", "fixed64", "float", "import", "int32", "int64", "map",
          "message", "oneof", "option", "package", "public", "repeated", "reserved", "rpc", "service", "sfixed32", "sfixed64",
          "sint32", "sint64", "stream", "string", "syntax", "to", "true", "uint32", "uint64", "weak"
        ].freeze
      end
    end
  end
end
