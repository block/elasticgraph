# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module JSONIngestion
    # Artifact providers for ElasticGraph's versioned JSON ingestion format.
    # Access through `schema_artifacts.extension_artifacts.fetch("json")`.
    module Artifacts
      # @param artifacts_dir [String] schema artifact directory
      # @param config [Hash] extension configuration (unused)
      # @return [FromDisk] provider for saved JSON schemas
      def self.from_disk(artifacts_dir, config:)
        require "elastic_graph/json_ingestion/artifacts/from_disk"
        FromDisk.new(artifacts_dir)
      end

      # @param results [ElasticGraph::SchemaDefinition::Results] schema results with JSON generation enabled
      # @param config [Hash] extension configuration (unused)
      # @return [FromSchemaDefinition] provider for generated JSON schemas
      def self.from_schema_definition(results, config:)
        require "elastic_graph/json_ingestion/artifacts/from_schema_definition"
        FromSchemaDefinition.new(results)
      end
    end
  end
end
