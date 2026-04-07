# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/json_schema_pruner"

module ElasticGraph
  module SchemaDefinition
    # Backward-compatible alias for the JSON schema pruner.
    #
    # @api private
    JSONSchemaPruner = JSONIngestion::SchemaDefinition::JSONSchemaPruner
  end
end
