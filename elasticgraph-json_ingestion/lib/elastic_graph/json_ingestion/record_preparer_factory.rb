# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/record_preparer"

module ElasticGraph
  module JSONIngestion
    # Provides the ability to get an `Indexer::RecordPreparer` for a specific JSON schema version,
    # deriving each version's per-type field metadata from that version's JSON schemas.
    class RecordPreparerFactory
      # @param schema_artifacts [SchemaArtifacts::FromDisk] the schema artifacts
      def initialize(schema_artifacts)
        @schema_artifacts = schema_artifacts

        scalar_types_by_name = schema_artifacts.runtime_metadata.scalar_types_by_name
        indexing_preparer_by_scalar_type_name = ::Hash.new do |hash, type_name|
          hash[type_name] = scalar_types_by_name[type_name]&.load_indexing_preparer&.extension_class
        end # : ::Hash[::String, SchemaArtifacts::RuntimeMetadata::extensionClass?]

        @preparers_by_json_schema_version = ::Hash.new do |hash, version|
          hash[version] = Indexer::RecordPreparer.new(
            indexing_preparer_by_scalar_type_name,
            build_type_metas_from(@schema_artifacts.json_schemas_for(version))
          )
        end
      end

      # Gets the `Indexer::RecordPreparer` for the given JSON schema version.
      #
      # @param json_schema_version [Integer] the JSON schema version
      # @return [Indexer::RecordPreparer] the record preparer for the given version
      def for_json_schema_version(json_schema_version)
        @preparers_by_json_schema_version[json_schema_version] # : Indexer::RecordPreparer
      end

      # Gets the `Indexer::RecordPreparer` for the latest JSON schema version. Intended primarily
      # for use in tests for convenience.
      #
      # @return [Indexer::RecordPreparer] the record preparer for the latest version
      def for_latest_json_schema_version
        for_json_schema_version(@schema_artifacts.latest_json_schema_version)
      end

      private

      def build_type_metas_from(json_schemas)
        json_schemas.fetch("$defs").filter_map do |type, type_def|
          next if type == EVENT_ENVELOPE_JSON_SCHEMA_NAME

          properties = type_def.fetch("properties") do
            {} # : ::Hash[::String, untyped]
          end # : ::Hash[::String, untyped]

          eg_meta_by_field_name = properties.filter_map do |prop_name, prop|
            eg_meta = prop["ElasticGraph"]
            [prop_name, eg_meta] if eg_meta
          end.to_h

          Indexer::RecordPreparer::TypeMetadata.new(
            name: type,
            eg_meta_by_field_name: eg_meta_by_field_name
          )
        end
      end
    end
  end
end
