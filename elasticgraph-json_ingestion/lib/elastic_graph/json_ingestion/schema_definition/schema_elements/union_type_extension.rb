# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/union"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module SchemaElements
        # Extends union types with JSON schema behavior.
        module UnionTypeExtension
          # @private
          def to_indexing_field_type
            field_type = super # : ElasticGraph::SchemaDefinition::Indexing::FieldType::Union
            Indexing::FieldType::Union.wrap(field_type)
          end
        end
      end
    end
  end
end
