# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/indexer/record_preparer"

module ElasticGraph
  module ProtoIngestion
    # Private indexing metadata emitted alongside the public protobuf definitions.
    # @private
    class RuntimeSchema
      # @dynamic types, package_name, record_preparer
      attr_reader :types, :package_name, :record_preparer

      def initialize(schema_artifacts)
        extension = schema_artifacts.runtime_metadata.indexer_extension_modules.find do |candidate|
          candidate.extension_ref.fetch("name") == "ElasticGraph::ProtoIngestion::IndexerExtension"
        end
        unless extension
          raise Errors::ConfigError, "Protobuf runtime metadata is missing. Enable ProtoIngestion::SchemaDefinition::APIExtension and dump schema artifacts."
        end
        config = extension.extension_ref.fetch("config")
        @types = config.fetch("types")
        @package_name = config.fetch("package_name")
        scalar_types = schema_artifacts.runtime_metadata.scalar_types_by_name
        preparers = scalar_types.transform_values { |scalar| scalar.load_indexing_preparer.extension_class }
        type_metas = types.filter_map do |name, metadata|
          if (fields = metadata["fields"])
            Indexer::RecordPreparer::TypeMetadata.new(name: name, fields_by_name: fields.transform_values do |field|
              Indexer::RecordPreparer::FieldMetadata.new(type: field.fetch("type"), name_in_index: field.fetch("name_in_index"))
            end)
          end
        end
        @record_preparer = Indexer::RecordPreparer.new(preparers, type_metas)
      end
    end
  end
end
