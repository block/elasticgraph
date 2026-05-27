# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/json_ingestion/schema_definition/json_schema_option_validator"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module SchemaElements
        # Extends scalar types with JSON schema validation and serialization behavior.
        module ScalarTypeExtension
          # @return [Hash<Symbol, Object>] JSON schema options for this scalar type
          def json_schema_options
            @json_schema_options ||= {}
          end

          # Defines the JSON Schema representation of this scalar type. This is required for custom scalar types
          # because ElasticGraph cannot infer how arbitrary scalars are represented in indexing events.
          #
          # Can be called multiple times; each call merges options into the existing set.
          #
          # @param options [Hash<Symbol, Object>] JSON schema options
          # @return [void]
          #
          # @example Define the JSON Schema representation of a custom scalar type
          #   ElasticGraph.define_schema do |schema|
          #     schema.scalar_type "URL" do |t|
          #       t.mapping type: "keyword"
          #       t.json_schema type: "string", format: "uri"
          #     end
          #   end
          def json_schema(**options)
            JSONSchemaOptionValidator.validate!(self, options)
            json_schema_options.update(options)
            self.runtime_metadata = runtime_metadata.with(grouping_missing_value_placeholder: inferred_grouping_missing_value_placeholder) unless grouping_missing_value_placeholder_overridden
          end

          # Validates that json_schema has been configured on this scalar type.
          #
          # @raise [Errors::SchemaError] if json_schema has not been configured
          # @return [void]
          def validate_json_schema_configuration!
            return unless json_schema_options.empty?

            raise Errors::SchemaError, "Scalar types require `json_schema` to be configured, but `#{name}` lacks `json_schema`."
          end

          private

          def inferred_grouping_missing_value_placeholder
            case mapping_type
            when "long"
              # It is only safe to use NaN for a long when the long's range is safe to coerce to a float
              # without loss of precision. This is because using NaN as the missing value will cause
              # the datastore to coerce the other bucket keys to float.
              # JSON schema min/max only constrains newly indexed values, not existing data that may fall
              # outside the range before the constraints were added. In that edge case, users can set
              # `grouping_missing_value_placeholder` to `nil`.
              if (json_schema_options[:minimum] || LONG_STRING_MIN) >= JSON_SAFE_LONG_MIN &&
                  (json_schema_options[:maximum] || LONG_STRING_MAX) <= JSON_SAFE_LONG_MAX
                inferred_numeric_placeholder_for_integer_type
              end
            when "unsigned_long"
              # Similar to the checks above for long except we only need to check the max
              # (since the min is zero even if not specified).
              if (json_schema_options[:maximum] || LONG_STRING_MAX) <= JSON_SAFE_LONG_MAX
                inferred_numeric_placeholder_for_integer_type
              end
            else
              super
            end
          end
        end
      end
    end
  end
end
