# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/field_type/union_extension"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Extends union types with JSON schema behavior.
      module UnionTypeExtension
        # @private
        def to_indexing_field_type
          FieldType::Union.new(super)
        end
      end
    end
  end
end
