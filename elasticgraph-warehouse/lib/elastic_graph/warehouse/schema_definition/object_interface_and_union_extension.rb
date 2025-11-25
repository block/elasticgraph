# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse/schema_definition/field_type_converter"
require "elastic_graph/warehouse/schema_definition/warehouse_table"

module ElasticGraph
  module Warehouse
    module SchemaDefinition
      # Extends {ElasticGraph::SchemaDefinition::SchemaElements::ObjectType},
      # {ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType}, and
      # {ElasticGraph::SchemaDefinition::SchemaElements::UnionType} to add warehouse table and column type definition support.
      module ObjectInterfaceAndUnionExtension
        # Sentinel value used to indicate that this type should be excluded from the data warehouse.
        EXCLUDED_FROM_WAREHOUSE = :excluded_from_warehouse
        private_constant :EXCLUDED_FROM_WAREHOUSE

        # Returns the warehouse table definition for this object or interface type.
        #
        # @return [ElasticGraph::Warehouse::SchemaDefinition::WarehouseTable, nil] the warehouse table definition, or nil if not defined
        def warehouse_table_def
          @warehouse_table_def
        end

        # Defines a warehouse table for this object or interface type.
        #
        # @param name [String] name of the warehouse table
        # @return [void]
        def warehouse_table(name)
          @warehouse_table_def = WarehouseTable.new(name, self)
        end

        # Excludes this indexed type from the data warehouse configuration.
        # This is useful when you have an indexed type but don't want it to be included
        # in the data warehouse.
        #
        # @return [void]
        #
        # @example Exclude an internal/test type from the warehouse
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "InternalMetrics" do |t|
        #       t.field "id", "ID"
        #       t.index "internal_metrics"
        #       t.exclude_from_warehouse  # This index won't be in the data warehouse
        #     end
        #   end
        def exclude_from_warehouse
          @warehouse_table_def = EXCLUDED_FROM_WAREHOUSE
        end

        # Hooks into the index method to automatically set warehouse_table based on the index name
        # if it hasn't been explicitly set. Users can still override by calling warehouse_table explicitly
        # or exclude it entirely by calling exclude_from_warehouse.
        #
        # @param name [String] name of the index
        # @param settings [Hash<Symbol, Object>] datastore index settings
        # @yield [Indexing::Index] the index, so it can be customized further
        # @return [void]
        def index(name, **settings, &block)
          super(name, **settings, &block)
          # Automatically set warehouse_table to match the index name if not already set
          warehouse_table(name) unless @warehouse_table_def
        end

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
