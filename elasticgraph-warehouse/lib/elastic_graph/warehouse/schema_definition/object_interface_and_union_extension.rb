# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/field_type_converter"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Extends {ElasticGraph::SchemaDefinition::SchemaElements::ObjectType},
      # {ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType}, and
      # {ElasticGraph::SchemaDefinition::SchemaElements::UnionType} to add warehouse column type conversion.
      module ObjectInterfaceAndUnionExtension
        # Returns the warehouse column type representation for this object, interface, or union type.
        #
        # @return [String] a STRUCT SQL type containing all subfields
        # @note For union types, the STRUCT includes all fields from all subtypes, following the same pattern used
        #   in the datastore mapping (see {ElasticGraph::SchemaDefinition::Indexing::FieldType::Union#to_mapping}).
        def to_warehouse_column_type
          subfields = indexing_fields_by_name_in_index.values.map(&:to_indexing_field).compact

          struct_field_expressions = subfields.map do |subfield|
            warehouse_type = FieldTypeConverter.convert(subfield.type)
            "#{subfield.name_in_index} #{warehouse_type}"
          end.join(", ")

          "STRUCT<#{struct_field_expressions}>"
        end
      end
    end
  end
end
