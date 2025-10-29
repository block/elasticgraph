# Copyright 2024 - 2025 Block, Inc.
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
        results = define_schema(
          schema_element_name_form: :snake_case,
          extension_modules: [SchemaDefinition::APIExtension],
          **options,
          &block
        )

        # Customization callbacks are applied from `results.all_types`, so we need to call it to
        # ensure our `on_built_in_types` callback is executed.
        #
        # TODO(jwils/myronmarston): figure out a better solution--the callback should be called automatically.
        results.send(:all_types)

        results
      end

      def warehouse_column_type_for(results, type)
        results.state.types_by_name.fetch(type).to_warehouse_column_type
      end
    end

    RSpec.configure do |config|
      config.include SchemaSupport, :warehouse_schema
    end
  end
end
