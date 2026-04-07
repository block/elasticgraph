# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/hash_util"
require "elastic_graph/support/json_schema/meta_schema_validator"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Validates JSON-schema-specific configuration supplied through schema definition APIs.
      #
      # @api private
      module JSONSchemaOptionValidator
        module_function

        # Validates JSON schema options against the JSON meta-schema.
        #
        # @param schema_element [Object] the schema element being configured (used in error messages)
        # @param options [Hash<Symbol, Object>] the JSON schema options to validate
        # @raise [Errors::SchemaError] if the options are invalid
        # @return [void]
        def validate!(schema_element, options)
          validatable_json_schema = Support::HashUtil.stringify_keys(options)

          if (error_msg = Support::JSONSchema.strict_meta_schema_validator.validate_with_error_message(validatable_json_schema))
            raise Errors::SchemaError, "Invalid JSON schema options set on #{schema_element}:\n\n#{error_msg}"
          end
        end
      end
    end
  end
end
