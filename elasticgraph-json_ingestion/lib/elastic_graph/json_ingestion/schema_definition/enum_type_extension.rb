# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/field_type/enum_extension"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Extends enum types with JSON schema behavior.
      module EnumTypeExtension
        # @private
        def configure_derived_scalar_type(scalar_type)
          super
          scalar_type.json_schema type: "string"
        end

        # @private
        def to_indexing_field_type
          FieldType::Enum.new(super)
        end
      end
    end
  end
end
