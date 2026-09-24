# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/proto_ingestion"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  module ProtoIngestion
    # Artifact providers for protobuf schemas, available as the `proto` schema artifact extension.
    module Artifacts
      # @param artifacts_dir [String] schema artifact directory
      # @param config [Hash] extension configuration (unused)
      # @return [FromDisk] provider for a saved protobuf schema
      def self.from_disk(artifacts_dir, config:)
        FromDisk.new(artifacts_dir)
      end

      # @param results [ElasticGraph::SchemaDefinition::Results] results with protobuf generation enabled
      # @param config [Hash] extension configuration (unused)
      # @return [FromSchemaDefinition] provider for a generated protobuf schema
      def self.from_schema_definition(results, config:)
        FromSchemaDefinition.new(results)
      end

      # Loads a protobuf schema from disk.
      # @!attribute [r] artifacts_dir
      #   @return [String] schema artifact directory
      # @!method initialize(artifacts_dir)
      #   @param artifacts_dir [String] schema artifact directory
      #   @return [void]
      class FromDisk < Support::MemoizableData.define(:artifacts_dir)
        # @return [String] protobuf schema source
        # @raise [Errors::MissingSchemaArtifactError] when the protobuf schema was not dumped
        def proto_schema
          @proto_schema ||= begin
            file = ::File.join(artifacts_dir, PROTO_SCHEMA_FILE)
            unless ::File.exist?(file)
              raise Errors::MissingSchemaArtifactError, "Schema artifact `#{PROTO_SCHEMA_FILE}` could not be found in `#{artifacts_dir}`. Regenerate the schema artifacts."
            end
            ::File.read(file)
          end
        end
      end

      # Exposes the protobuf schema generated in memory.
      # @!attribute [r] results
      #   @return [ElasticGraph::SchemaDefinition::Results] results with protobuf generation enabled
      # @!method initialize(results)
      #   @param results [ElasticGraph::SchemaDefinition::Results] results with protobuf generation enabled
      #   @return [void]
      class FromSchemaDefinition < Support::MemoizableData.define(:results)
        # @return [String] protobuf schema source
        # @raise [Errors::MissingSchemaArtifactError] when no protobuf messages were generated
        def proto_schema
          schema = results.proto_schema
          if schema.empty?
            raise Errors::MissingSchemaArtifactError, "Schema artifact `#{PROTO_SCHEMA_FILE}` is unavailable because the schema has no protobuf messages to generate."
          end
          schema
        end
      end
    end
  end
end
