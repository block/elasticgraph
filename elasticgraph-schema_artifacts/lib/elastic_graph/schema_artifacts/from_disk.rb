# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/artifacts_helper_methods"
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

      # Provides the JSON schemas of all types at a specific version. The JSON schemas define the contract between
      # data publishers and an ElasticGraph project, and can be freely given to data publishers for code generation
      # or query validation purposes.
      #
      # In addition, they are used by `elasticgraph-indexer` to validate data before indexing it.
      #
      # @note ElasticGraph supports multiple JSON schema versions in order to support safe, seamless schema evolution.
      #   Each event will be validated using the version specified in the event itself, allowing data publishers to be
      #   updated to the latest JSON schema at a later time after `elasticgraph-indexer` is deployed with a new JSON
      #   schema version.
      #
      # @param version [Integer] the desired JSON schema version
      # @return [Hash<String, Object>]
      # @raise [Errors::MissingSchemaArtifactError] when the provided version does not exist within the `artifacts_dir`.
      # @see #available_json_schema_versions
      # @see #latest_json_schema_version
      #
      # @example Get the JSON schema for a `Widget` type at version 1
      #   artifacts = ElasticGraph::SchemaArtifacts::FromDisk.new(schema_artifacts_dir)
      #   widget_v1_json_schema = artifacts.json_schemas_for(1).fetch("$defs").fetch("Widget")
      def json_schemas_for(version)
        unless available_json_schema_versions.include?(version)
          raise Errors::MissingSchemaArtifactError, "The requested json schema version (#{version}) is not available. " \
            "Available versions: #{available_json_schema_versions.sort.join(", ")}."
        end

        json_schemas_by_version[version] # : ::Hash[::String, untyped]
      end

      # Provides the set of available JSON schema versions.
      #
      # @return [Set<Integer>]
      # @see #json_schemas_for
      # @see #latest_json_schema_version
      #
      # @example Print the list of available JSON schema versions
      #   artifacts = ElasticGraph::SchemaArtifacts::FromDisk.new(schema_artifacts_dir)
      #   puts artifacts.available_json_schema_versions.sort.join(", ")
      def available_json_schema_versions
        @available_json_schema_versions ||= begin
          versioned_json_schemas_dir = ::File.join(artifacts_dir, JSON_SCHEMAS_BY_VERSION_DIRECTORY)
          if ::Dir.exist?(versioned_json_schemas_dir)
            ::Dir.entries(versioned_json_schemas_dir).filter_map { |it| it[/v(\d+)\.yaml/, 1]&.to_i }.to_set
          else
            ::Set.new
          end
        end
      end

      # Provides the latest JSON schema version.
      #
      # @return [Integer]
      # @raise [Errors::MissingSchemaArtifactError] when no JSON schemas files exist within the `artifacts_dir`.
      # @see #available_json_schema_versions
      # @see #json_schemas_for
      #
      # @example Print the latest JSON schema version
      #   artifacts = ElasticGraph::SchemaArtifacts::FromDisk.new(schema_artifacts_dir)
      #   puts artifacts.latest_json_schema_version
      def latest_json_schema_version
        @latest_json_schema_version ||= available_json_schema_versions.max || raise(
          Errors::MissingSchemaArtifactError,
          "The directory for versioned JSON schemas (#{::File.join(artifacts_dir, JSON_SCHEMAS_BY_VERSION_DIRECTORY)}) could not be found. " \
          "Either the schema artifacts haven't been dumped yet or the schema artifacts directory (#{artifacts_dir}) is misconfigured."
        )
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

      def json_schemas_by_version
        @json_schemas_by_version ||= ::Hash.new do |hash, json_schema_version|
          hash[json_schema_version] = load_json_schema(json_schema_version)
        end
      end

      # Loads the given JSON schema version from disk.
      def load_json_schema(json_schema_version)
        parsed_yaml_from(::File.join(JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v#{json_schema_version}.yaml"))
      end
    end
  end
end
