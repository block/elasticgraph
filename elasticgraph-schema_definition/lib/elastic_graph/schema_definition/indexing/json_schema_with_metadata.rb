# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/json_schema_with_metadata"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Backward-compatible alias for the JSON schema merge result type.
      #
      # @api private
      JSONSchemaWithMetadata = JSONIngestion::SchemaDefinition::Indexing::JSONSchemaWithMetadata
    end
  end
end
