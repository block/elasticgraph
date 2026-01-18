# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/test_support"
require "elastic_graph/warehouse/schema_definition/api_extension"

module ElasticGraph
  module Warehouse
    module SchemaSupport
      include ElasticGraph::SchemaDefinition::TestSupport

      def define_warehouse_schema(**options, &block)
        define_schema(
          schema_element_name_form: :snake_case,
          extension_modules: [SchemaDefinition::APIExtension],
          **options,
          &block
        )
        # Note: `warehouse_config` automatically triggers `all_types` which applies
        # customization callbacks. No need to call it manually here.
      end

      def table_schema_from(results, table_name)
        results.warehouse_config.fetch("tables").fetch(table_name).fetch("table_schema")
      end

      def warehouse_column_def_from(results, table_name, column_name)
        table_schema_from(results, table_name)
          .lines
          .map(&:strip)
          .find { |line| line.start_with?("#{column_name} ") }
          .sub(/,?\z/, "")
      end

      def table_names_from(results)
        results.warehouse_config["tables"].keys
      end
    end

    RSpec.configure do |config|
      config.include SchemaSupport, :warehouse_schema
    end
  end
end
