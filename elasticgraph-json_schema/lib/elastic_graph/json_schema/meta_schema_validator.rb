# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_schema/validator"
require "elastic_graph/json_schema/validator_factory"
require "elastic_graph/support/hash_util"
require "json"

module ElasticGraph
  # Provides [JSON Schema](https://json-schema.org/) validation for ElasticGraph.
  module JSONSchema
    # Provides a validator to validate a JSON schema definitions according to the JSON schema meta schema.
    # The validator is configured to validate strictly, so that non-standard JSON schema properties are disallowed.
    #
    # @return [Validator]
    # @see .elastic_graph_internal_meta_schema_validator
    def self.strict_meta_schema_validator
      @strict_meta_schema_validator ||= MetaSchemaLoader.load_strict_validator
    end

    # Provides a validator to validate a JSON schema definition according to the JSON schema meta schema.
    # The validator is configured to validate strictly, so that non-standard JSON schema properties are disallowed,
    # except for internal ElasticGraph metadata properties.
    #
    # @return [Validator]
    # @see .strict_meta_schema_validator
    def self.elastic_graph_internal_meta_schema_validator
      @elastic_graph_internal_meta_schema_validator ||= MetaSchemaLoader.load_strict_validator({
        "properties" => {
          "ElasticGraph" => {
            "type" => "object",
            "required" => ["type", "nameInIndex"],
            "properties" => {
              "type" => {"type" => "string"},
              "nameInIndex" => {"type" => "string"}
            }
          }
        }
      })
    end

    # Responsible for building {Validator}s that can validate JSON schema definitions.
    module MetaSchemaLoader
      # Builds a validator to validate a JSON schema definition according to the JSON schema meta schema.
      #
      # @param overrides [Hash<String, Object>] meta schema overrides
      def self.load_strict_validator(overrides = {})
        # Downloaded from: https://json-schema.org/draft-07/schema
        schema = ::JSON.parse(::File.read(::File.expand_path("../json_schema_draft_7_schema.json", __FILE__)))
        schema = Support::HashUtil.deep_merge(schema, overrides) unless overrides.empty?

        # The meta schema allows additionalProperties in nearly every place. While a JSON schema definition
        # with additional properties is considered valid, we do not intend to use any additional properties,
        # and any usage of an additional property is almost certainly a typo. So here we set
        # `with_unknown_properties_disallowed`.
        root_schema = ValidatorFactory.new(schema: schema, sanitize_pii: false) # The meta schema has no PII
          .with_unknown_properties_disallowed
          .root_schema

        Validator.new(schema: root_schema, sanitize_pii: false)
      end
    end
  end
end
