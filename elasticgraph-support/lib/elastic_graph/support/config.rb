# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/support/json_schema/validator_factory"
require "elastic_graph/support/from_yaml_file"
require "elastic_graph/support/hash_util"
require "json_schemer"

module ElasticGraph
  module Support
    # Provides a standard way to define an ElasticGraph configuration class.
    module Config
      # Defines a configuration class with the given attributes.
      #
      # @param attrs [::Symbol] attribute names
      # @return [::Class] the defined configuration class
      # @yield [::Data] the body of the class (similar to `::Data.define`)
      #
      # @example Define a configuration class
      #    require "elastic_graph/support/config"
      #
      #    ExampleConfigClass = ElasticGraph::Support::Config.define(:size, :name) do
      #      json_schema at: "example", optional: false,
      #        properties: {
      #          size: {
      #            description: "Determines the size.",
      #            examples: [10, 100],
      #            type: "integer",
      #            minimum: 1,
      #          },
      #          name: {
      #            description: "Determines the name.",
      #            examples: ["widget"],
      #            type: "string",
      #            minLength: 1
      #          }
      #        },
      #        required: ["size", "name"]
      #    end
      def self.define(*attrs, &block)
        ::Data.define(*attrs) do
          # @implements ::Data
          alias_method :__data_initialize, :initialize
          extend ClassMethods
          include InstanceMethods

          class_exec(&(_ = block)) if block
        end
      end

      # Defines class methods for configuration classes.
      module ClassMethods
        include Support::FromYamlFile

        # @dynamic validator, path, required

        # @return [Support::JSONSchema::Validator] validator for this configuration class
        attr_reader :validator

        # @return [::String] path from the global configuration root to where this configuration resides.
        attr_reader :path

        # @return [::Boolean] whether this configuration property is required
        attr_reader :required

        # Defines the JSON schema and path for this configuration class.
        #
        # @param at [::String] path from the global configuration root to where this configuration resides
        # @param optional [::Boolean] whether configuration at the provided `path` is optional
        # @param schema [::Hash<::Symbol, ::Object>] JSON schema definition
        # @return [void]
        #
        # @example Define a configuration class
        #    require "elastic_graph/support/config"
        #
        #    ExampleConfigClass = ElasticGraph::Support::Config.define(:size, :name) do
        #      json_schema at: "example", optional: false,
        #        properties: {
        #          size: {
        #            description: "Determines the size.",
        #            examples: [10, 100],
        #            type: "integer",
        #            minimum: 1,
        #          },
        #          name: {
        #            description: "Determines the name.",
        #            examples: ["widget"],
        #            type: "string",
        #            minLength: 1
        #          }
        #        },
        #        required: ["size", "name"]
        #    end
        def json_schema(at:, optional:, **schema)
          @path = at
          @required = !optional

          schema = Support::HashUtil.stringify_keys(schema)
          @validator = Support::JSONSchema::ValidatorFactory
            .new(schema: {"$schema" => "http://json-schema.org/draft-07/schema#", "$defs" => {"config" => schema}}, sanitize_pii: false)
            .with_unknown_properties_disallowed
            .validator_for("config")
        end

        # Instantiates a config instance from the given parsed YAML class, returning `nil` if there is no config.
        # In addition, this (along with `Support::FromYamlFile`) makes `from_yaml_file(path_to_file)` available.
        #
        # @param parsed_yaml [::Hash<::String, ::Object>] config hash parsed from YAML
        # @return [::Data, nil] the instantiated config object or `nil` if there is nothing at the specified path
        def from_parsed_yaml(parsed_yaml)
          value_at_path = Support::HashUtil.fetch_value_at_path(parsed_yaml, path.split(".")) { return nil }

          if value_at_path.is_a?(::Hash)
            config = (_ = value_at_path).transform_keys(&:to_sym) # : ::Hash[::Symbol, untyped]
            new(**config)
          else
            raise_invalid_config("Expected a hash at `#{path}`, got: `#{value_at_path.inspect}`.")
          end
        end

        # Instantiates a config instance from the given parsed YAML class, raising an error if there is no config.
        #
        # @param parsed_yaml [::Hash<::String, ::Object>] config hash parsed from YAML
        # @return [::Data] the instantiated config object
        # @raise [Errors::ConfigError] if there is no config at the specified path.
        def from_parsed_yaml!(parsed_yaml)
          from_parsed_yaml(parsed_yaml) || raise_invalid_config("missing configuration at `#{path}`.")
        end

        # @private
        def raise_invalid_config(error)
          raise Errors::ConfigError, "Invalid configuration for `#{name}` at `#{path}`: #{error}"
        end

        # Like `new`, but avoids applying JSON schema validation. This is needed so that we can make
        # `#with` work correctly with the validation and conversion features we offer.
        #
        # @private
        def new_without_validation(**data)
          instance = allocate
          instance.send(:__data_initialize, **data)
          instance
        end
      end

      # @private
      module InstanceMethods
        # Overrides `initialize` to apply JSON schema validation.
        def initialize(**config)
          klass = (_ = self.class) # : ClassMethods[::Data]
          validator = klass.validator
          config = validator.merge_defaults(config)

          if (error = validator.validate_with_error_message(config))
            klass.raise_invalid_config(error)
          end

          config = config.transform_keys(&:to_sym)
          __skip__ = super(**convert_values(**config))
        end

        # Overrides `#with` to bypass the normal JSON schema validation that applies in `#initialize`.
        # This is required so that `config.with(...)` can be used on config classes that use the
        # `convert_values` hook to convert JSON data to some custom Ruby type. The custom Ruby type
        # won't pass JSON schema validation, and if we didn't override `with` then we'd get validation
        # failures due to the converted values failing validation.
        def with(**updates)
          (_ = self.class).new_without_validation(**to_h.merge(updates))
        end

        private

        # Default implementation of a hook that allows config values to be converted during initialization.
        def convert_values(**values)
          values
        end
      end
    end
  end
end
