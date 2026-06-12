# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/protobuf/schema_definition/identifier"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      # Extends EnumType with proto field type conversion.
      module EnumTypeExtension
        # Returns the proto field type representation for this enum type.
        #
        # @return [String]
        def to_proto_field_type
          Identifier.enum_name(name)
        end
      end
    end
  end
end
