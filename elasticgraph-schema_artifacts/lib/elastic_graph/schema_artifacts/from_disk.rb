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
require "elastic_graph/support/hash_util"
require "elastic_graph/support/memoizable_data"
require "yaml"

module ElasticGraph
  module SchemaArtifacts
    # Builds a `SchemaArtifacts::FromDisk` instance using the provided YAML settings.
    def self.from_parsed_yaml(parsed_yaml, for_context:)
      schema_artifacts = parsed_yaml.fetch("schema_artifacts") do
        raise Errors::ConfigError, "Config is missing required key `schema_artifacts`."
      end

      if (extra_keys = schema_artifacts.keys - ["directory"]).any?
        raise Errors::ConfigError, "Config has extra `schema_artifacts` keys: #{extra_keys}"
      end

      directory = schema_artifacts.fetch("directory") do
        raise Errors::ConfigError, "Config is missing required key `schema_artifacts.directory`."
      end

      FromDisk.new(directory, for_context)
    end

    # Responsible for loading schema artifacts from disk.
    class FromDisk < Support::MemoizableData.define(:artifacts_dir, :context)
      include ArtifactsHelperMethods

      def graphql_schema_string
        @graphql_schema_string ||= read_artifact(GRAPHQL_SCHEMA_FILE)
      end

      def json_schemas_for(version)
        unless available_json_schema_versions.include?(version)
          raise Errors::MissingSchemaArtifactError, "The requested json schema version (#{version}) is not available. " \
            "Available versions: #{available_json_schema_versions.sort.join(", ")}."
        end

        json_schemas_by_version[version] # : ::Hash[::String, untyped]
      end

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

      def latest_json_schema_version
        @latest_json_schema_version ||= available_json_schema_versions.max || raise(
          Errors::MissingSchemaArtifactError,
          "The directory for versioned JSON schemas (#{::File.join(artifacts_dir, JSON_SCHEMAS_BY_VERSION_DIRECTORY)}) could not be found. " \
          "Either the schema artifacts haven't been dumped yet or the schema artifacts directory (#{artifacts_dir}) is misconfigured."
        )
      end

      def datastore_config
        @datastore_config ||= _ = parsed_yaml_from(DATASTORE_CONFIG_FILE)
      end

      def runtime_metadata
        @runtime_metadata ||= RuntimeMetadata::Schema.from_hash(
          parsed_yaml_from(RUNTIME_METADATA_FILE),
          for_context: context
        )
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
