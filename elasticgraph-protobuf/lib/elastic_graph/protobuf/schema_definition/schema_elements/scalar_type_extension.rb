# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      module SchemaElements
        # Extends ScalarType with proto field type conversion.
        module ScalarTypeExtension
          # Configured proto field type (e.g. string, int64, bool).
          # @dynamic proto_field_type
          attr_reader :proto_field_type

          # Configures the proto field type for this scalar type.
          #
          # @param type [String] protobuf scalar type name
          # @return [void]
          def proto_field(type:)
            @proto_field_type = type
          end

          # Returns this scalar's proto field type.
          #
          # @return [String]
          # @raise [Errors::SchemaError] when missing
          def to_proto_field_type
            proto_field_type ||
              raise(Errors::SchemaError, "Protobuf field type not configured for scalar type `#{name}`. " \
                'To proceed, call `proto_field type: "TYPE"` on the scalar type definition.')
          end
        end
      end
    end
  end
end
