# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto/schema_definition/identifier"

module ElasticGraph
  module Proto
    module SchemaDefinition
      # Extends object/interface/union types with proto field type conversion.
      module ObjectInterfaceAndUnionExtension
        # Returns the proto field type representation for this type.
        #
        # @return [String]
        def to_proto_field_type
          Identifier.message_name(name)
        end
      end
    end
  end
end
