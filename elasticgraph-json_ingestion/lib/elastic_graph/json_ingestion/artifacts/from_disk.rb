# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/support/memoizable_data"
require "yaml"

module ElasticGraph
  module JSONIngestion
    module Artifacts
      # Loads versioned JSON schemas from the schema artifact directory.
      # @!attribute [r] artifacts_dir
      #   @return [String] schema artifact directory
      # @!method initialize(artifacts_dir)
      #   @param artifacts_dir [String] schema artifact directory
      #   @return [void]
      class FromDisk < Support::MemoizableData.define(:artifacts_dir)
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
        #   artifacts = ElasticGraph::JSONIngestion::Artifacts::FromDisk.new(schema_artifacts_dir)
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
        #   artifacts = ElasticGraph::JSONIngestion::Artifacts::FromDisk.new(schema_artifacts_dir)
        #   puts artifacts.available_json_schema_versions.sort.join(", ")
        def available_json_schema_versions
          @available_json_schema_versions ||= begin
            versioned_json_schemas_dir = ::File.join(artifacts_dir, JSON_SCHEMAS_BY_VERSION_DIRECTORY)
            if ::Dir.exist?(versioned_json_schemas_dir)
              ::Dir.entries(versioned_json_schemas_dir).filter_map { |filename| filename[/v(\d+)\.yaml/, 1]&.to_i }.to_set
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
        #   artifacts = ElasticGraph::JSONIngestion::Artifacts::FromDisk.new(schema_artifacts_dir)
        #   puts artifacts.latest_json_schema_version
        def latest_json_schema_version
          @latest_json_schema_version ||= available_json_schema_versions.max || raise(
            Errors::MissingSchemaArtifactError,
            "The directory for versioned JSON schemas (#{::File.join(artifacts_dir, JSON_SCHEMAS_BY_VERSION_DIRECTORY)}) could not be found. " \
            "Either the schema artifacts haven't been dumped yet or the schema artifacts directory (#{artifacts_dir}) is misconfigured."
          )
        end

        private

        def parsed_yaml_from(artifact_name)
          ::YAML.safe_load_file(::File.join(artifacts_dir, artifact_name))
        end

        def json_schemas_by_version
          @json_schemas_by_version ||= ::Hash.new do |hash, raw_json_schema_version|
            json_schema_version = raw_json_schema_version # : Integer
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
end
