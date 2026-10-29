# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/proto_ingestion/runtime_metadata/type"

module ElasticGraph
  module ProtoIngestion
    # Generated metadata describing native protobuf records and their ElasticGraph meaning.
    #
    # @private
    module RuntimeMetadata
      # Configuration stored with the protobuf indexer extension.
      #
      # @private
      Schema = ::Data.define(:package_name, :types_by_name) do
        # @implements Schema

        def self.from_schema_artifacts(schema_artifacts)
          extension = schema_artifacts.runtime_metadata.indexer_extension_modules.find do |candidate|
            candidate.extension_ref.fetch("name") == "ElasticGraph::ProtoIngestion::IndexerExtension"
          end
          unless extension
            raise Errors::ConfigError, "Protobuf runtime metadata is missing. Enable ProtoIngestion::SchemaDefinition::APIExtension and dump schema artifacts."
          end
          from_hash(extension.extension_ref.fetch("config"))
        end

        def self.from_hash(hash)
          types = hash["types_by_name"] || {} # : ::Hash[::String, untyped]
          new(
            package_name: hash.fetch("package_name"),
            types_by_name: types.transform_values { |type| Type.from_hash(type) }
          )
        end

        def to_dumpable_hash
          {
            "package_name" => package_name,
            "types_by_name" => types_by_name.sort.to_h.transform_values(&:to_dumpable_hash)
          }
        end
      end
    end
  end
end
