# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion"
require "elastic_graph/json_ingestion/schema_definition/api_extension"
require "elastic_graph/schema_definition/test_support"

module ElasticGraph
  module JSONIngestion
    module SchemaSupport
      include ElasticGraph::SchemaDefinition::TestSupport

      def define_json_ingestion_schema(**options, &block)
        define_schema(
          schema_element_name_form: :snake_case,
          **options,
          &block
        )
      end
    end
  end
end

RSpec.configure do |config|
  config.include ElasticGraph::JSONIngestion::SchemaSupport, :json_ingestion_schema
end
