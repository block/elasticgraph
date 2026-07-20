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
      # Helpers for validating Protocol Buffers package names. Other emitted identifiers come from
      # GraphQL names, whose lexical grammar matches the Protocol Buffers identifier grammar.
      class Identifier
        # Matches a single valid protobuf package segment.
        # https://protobuf.dev/reference/protobuf/proto3-spec/#identifiers
        VALID_PACKAGE_SEGMENT = /\A[A-Za-z_][A-Za-z0-9_]*\z/

        class << self
          # Validates a protobuf package identifier.
          #
          # @param name [String]
          # @return [String]
          def validate_package_name(name)
            if !name.is_a?(String) || name.empty?
              raise Errors::SchemaError, "`package_name` must be a non-empty String"
            end

            segments = name.split(".", -1)

            if segments.empty? || segments.any? { |segment| !VALID_PACKAGE_SEGMENT.match?(segment) }
              raise Errors::SchemaError, "`package_name` must be a dot-separated list of protobuf identifiers " \
                "(each starting with a letter or underscore, containing only letters, digits, and underscores), " \
                "got: #{name.inspect}."
            end

            name
          end
        end
      end
    end
  end
end
