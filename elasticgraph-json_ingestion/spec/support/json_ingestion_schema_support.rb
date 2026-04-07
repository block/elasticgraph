# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/test_support"
require "elastic_graph/json_ingestion/schema_definition/api_extension"

module ElasticGraph
  module JSONIngestion
    module SchemaSupport
      include ElasticGraph::SchemaDefinition::TestSupport

      def define_json_ingestion_schema(**options, &block)
        define_schema(
          schema_element_name_form: :snake_case,
          ingestion_serializer_extension_modules: [SchemaDefinition::APIExtension],
          **options,
          &block
        )
      end
    end

    RSpec.configure do |config|
      config.include SchemaSupport, :json_ingestion_schema
    end
  end
end
