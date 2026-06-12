# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      # Helpers for rendering Protocol Buffers identifiers while avoiding keyword conflicts.
      class Identifier
        # Builds a protobuf package identifier and escapes reserved keywords in each segment.
        #
        # @param name [#to_s]
        # @return [String]
        def self.package_name(name)
          name.to_s.split(".").map { |part| escape_keyword(part) }.join(".")
        end

        # Builds a protobuf message identifier.
        #
        # @param name [#to_s]
        # @return [String]
        def self.message_name(name)
          escape_keyword(name.to_s)
        end

        # Builds a protobuf enum identifier.
        #
        # @param name [#to_s]
        # @return [String]
        def self.enum_name(name)
          escape_keyword(name.to_s)
        end

        # Builds a protobuf field identifier.
        #
        # @param name [#to_s]
        # @return [String]
        def self.field_name(name)
          escape_keyword(name.to_s)
        end

        # Builds a protobuf enum value identifier.
        #
        # @param name [#to_s]
        # @return [String]
        def self.enum_value_name(name)
          escape_keyword(name.to_s)
        end

        # Escapes protobuf reserved keywords by suffixing them with an underscore.
        #
        # @param identifier [String]
        # @return [String]
        def self.escape_keyword(identifier)
          return identifier unless PROTO_KEYWORDS.include?(identifier)
          "#{identifier}_"
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
