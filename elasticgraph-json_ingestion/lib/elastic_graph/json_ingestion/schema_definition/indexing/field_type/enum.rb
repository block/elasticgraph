# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/enum_extension"
require "elastic_graph/schema_definition/indexing/field_type/enum"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        # Namespace for JSON-ingestion indexing field type wrappers.
        module FieldType
          # JSON-ingestion indexing field type wrapper for enums.
          #
          # @private
          class Enum
            include EnumExtension

            def self.wrap(field_type)
              new(field_type)
            end

            def initialize(field_type)
              @field_type = field_type
            end

            def enum_value_names
              @field_type.enum_value_names
            end

            def to_mapping
              @field_type.to_mapping
            end
          end
        end
      end
    end
  end
end
