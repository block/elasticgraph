# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/object"
require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/union"
require "elastic_graph/json_ingestion/schema_definition/json_schema_option_validator"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Extends object and interface types with JSON schema behavior.
      module ObjectInterfaceExtension
        # @return [Hash<Symbol, Object>] JSON schema options for this type
        def json_schema_options
          @json_schema_options ||= {}
        end

        # Configures JSON schema options for this object or interface type.
        #
        # @param options [Hash<Symbol, Object>] JSON schema options
        # @return [void]
        def json_schema(**options)
          JSONSchemaOptionValidator.validate!(self, options)
          json_schema_options.update(options)
        end

        # @private
        def to_indexing_field_type
          field_type = super

          if field_type.is_a?(ElasticGraph::SchemaDefinition::Indexing::FieldType::Union)
            Indexing::FieldType::Union.new(field_type)
          else
            Indexing::FieldType::Object.new(field_type, json_schema_options: json_schema_options)
          end
        end
      end
    end
  end
end
