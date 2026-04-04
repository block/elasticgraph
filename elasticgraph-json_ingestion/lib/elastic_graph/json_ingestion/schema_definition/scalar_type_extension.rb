# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/field_type/scalar_extension"
require "elastic_graph/json_ingestion/schema_definition/json_schema_option_validator"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Extends scalar types with JSON schema validation and serialization behavior.
      module ScalarTypeExtension
        # @return [Hash<Symbol, Object>] JSON schema options for this scalar type
        def json_schema_options
          @json_schema_options ||= {}
        end

        # Configures JSON schema options for this scalar type.
        #
        # @param options [Hash<Symbol, Object>] JSON schema options
        # @return [void]
        def json_schema(**options)
          JSONSchemaOptionValidator.validate!(self, options)
          json_schema_options.update(options)
        end

        # @private
        def to_indexing_field_type
          FieldType::Scalar.new(super)
        end

        # Validates that json_schema has been configured on this scalar type.
        #
        # @raise [Errors::SchemaError] if json_schema has not been configured
        # @return [void]
        def validate_json_schema_configuration!
          return unless json_schema_options.empty?

          raise Errors::SchemaError, "Scalar types require `json_schema` to be configured, but `#{name}` lacks `json_schema`."
        end
      end
    end
  end
end
