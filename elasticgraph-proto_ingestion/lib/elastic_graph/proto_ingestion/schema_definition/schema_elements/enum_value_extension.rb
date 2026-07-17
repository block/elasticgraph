# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/identifier"
require "elastic_graph/support/casing"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      module SchemaElements
        # Extends enum values with protobuf naming behavior.
        module EnumValueExtension
          # Returns this enum value's name in protobuf schemas.
          #
          # @param enum_value_prefix [String] normalized prefix of the containing enum
          # @return [String]
          def proto_name(enum_value_prefix)
            @proto_name ||= Identifier.enum_value_name("#{enum_value_prefix}_#{Support::Casing.to_upper_snake(name)}")
          end
        end
      end
    end
  end
end
