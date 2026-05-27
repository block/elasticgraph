# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/json_schema_option_validator"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module SchemaElements
        # Extends object and interface types with JSON schema behavior.
        module ObjectInterfaceExtension
          # @return [Hash<Symbol, Object>] JSON schema options for this type
          def json_schema_options
            @json_schema_options ||= {}
          end

          # Configures JSON Schema options for this object or interface type.
          #
          # Can be called multiple times; each call merges options into the existing set. When options are present,
          # they replace ElasticGraph's generated object schema for this type.
          #
          # @param options [Hash<Symbol, Object>] JSON schema options
          # @return [void]
          def json_schema(**options)
            JSONSchemaOptionValidator.validate!(self, options)
            json_schema_options.update(options)
          end

          # @private
          def to_indexing_field_type
            # @type var field_type: Indexing::FieldType::Object | Indexing::FieldType::Union
            field_type = _ = super
            return field_type unless field_type.is_a?(Indexing::FieldType::Object)

            Indexing::FieldType::Object.new(field_type.__getobj__, json_schema_options: json_schema_options)
          end
        end
      end
    end
  end
end
