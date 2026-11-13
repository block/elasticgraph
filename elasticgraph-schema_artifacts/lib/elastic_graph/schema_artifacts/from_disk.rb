# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/artifacts_helper_methods"
require "elastic_graph/schema_artifacts/extension_artifacts"
require "elastic_graph/schema_artifacts/runtime_metadata/schema"
require "elastic_graph/support/memoizable_data"
require "yaml"

module ElasticGraph
  module SchemaArtifacts
    # Responsible for loading schema artifacts from disk and providing access to each artifact.
    #
    # @!attribute [r] artifacts_dir
    #   @return [String] directory from which the schema artifacts are loaded
    #
    # @!method initialize(artifacts_dir)
    #   Builds an instance using the given artifacts directory.
    #   @param artifacts_dir [String] directory from which the schema artifacts are loaded
    #   @return [void]
    class FromDisk < Support::MemoizableData.define(:artifacts_dir)
      include ArtifactsHelperMethods

      # Provides the GraphQL SDL schema string. This defines the contract between an ElasticGraph project and its GraphQL clients,
      # and can be freely given to GraphQL clients for code generation or query validation purposes.
      #
      # In addition, it is used by `elasticgraph-graphql` to power an ElasticGraph GraphQL endpoint.
      #
      # @return [String]
      # @raise [Errors::MissingSchemaArtifactError] when the `graphql.schema` file does not exist in the `artifacts_dir`.
      #
      # @example Print the GraphQL schema string
      #   artifacts = ElasticGraph::SchemaArtifacts::FromDisk.new(schema_artifacts_dir)
      #   puts artifacts.graphql_schema_string
      #
      def graphql_schema_string
        @graphql_schema_string ||= read_artifact(GRAPHQL_SCHEMA_FILE)
      end

      # @return [ExtensionArtifacts] lazily constructed extension-owned artifact providers
      def extension_artifacts
        @extension_artifacts ||= ExtensionArtifacts.new(runtime_metadata.schema_artifact_extensions) do |factory, config|
          factory.from_disk(artifacts_dir, config: config)
        end
      end

      # Provides the datastore configuration. The datastore configuration defines the full configuration--including indices, templates,
      # and scripts--required in the datastore (Elasticsearch or OpenSearch) by ElasticGraph for the current schema.
      #
      # `elasticgraph-admin` uses this artifact to administer the datastore.
      #
      # @return [Hash<String, Object>]
      # @raise [Errors::MissingSchemaArtifactError] when `datastore_config.yaml` does not exist within the `artifacts_dir`.
      #
      # @example Print the current list of indices
      #   artifacts = ElasticGraph::SchemaArtifacts::FromDisk.new(schema_artifacts_dir)
      #   puts artifacts.datastore_config.fetch("indices").keys.sort.join(", ")
      def datastore_config
        @datastore_config ||= _ = parsed_yaml_from(DATASTORE_CONFIG_FILE)
      end

      # Provides the runtime metadata. This runtime metadata is used at runtime by `elasticgraph-graphql` and `elasticgraph-indexer`.
      #
      # @return [RuntimeMetadata::Schema]
      def runtime_metadata
        @runtime_metadata ||= RuntimeMetadata::Schema.from_hash(parsed_yaml_from(RUNTIME_METADATA_FILE))
      end

      private

      def read_artifact(artifact_name)
        file_name = ::File.join(artifacts_dir, artifact_name)

        if ::File.exist?(file_name)
          ::File.read(file_name)
        else
          raise Errors::MissingSchemaArtifactError, "Schema artifact `#{artifact_name}` could not be found. " \
            "Either the schema artifacts haven't been dumped yet or the schema artifacts directory (#{artifacts_dir}) is misconfigured."
        end
      end

      def parsed_yaml_from(artifact_name)
        ::YAML.safe_load(read_artifact(artifact_name))
      end
    end
  end
end
