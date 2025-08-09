# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/memoizable_data"
require "json"

module ElasticGraph
  module Support
    module JSONSchema
      # Responsible for validating JSON data against the ElasticGraph JSON schema for a particular type.
      #
      # @!attribute [r] schema
      #   @return [Hash<String, Object>] a JSON schema
      # @!attribute [r] sanitize_pii
      #   @return [Boolean] whether to omit data that may contain PII from error messages
      class Validator < MemoizableData.define(:schema, :sanitize_pii)
        # Validates the given data against the JSON schema, returning true if the data is valid.
        #
        # @param data [Object] JSON data to validate
        # @return [Boolean] true if the data is valid; false if it is invalid
        #
        # @see #validate
        # @see #validate_with_error_message
        def valid?(data)
          schema.valid?(data)
        end

        # Validates the given data against the JSON schema, returning an array of error objects for
        # any validation errors.
        #
        # @param data [Object] JSON data to validate
        # @return [Array<Hash<String, Object>>] validation errors; will be empty if `data` is valid
        #
        # @see #valid?
        # @see #validate_with_error_message
        def validate(data)
          schema.validate(data).map do |error|
            # The schemas can be very large and make the output very noisy, hiding what matters. So we remove them here.
            error.delete("root_schema")
            error.delete("schema")
            error
          end
        end

        # Validates the given data against the JSON schema, returning an error message string if it is invalid.
        # The error message is intended to be usable to include in a log message or a raised error.
        #
        # @param data [Object] JSON data to validate
        # @return [nil, String] a validation error message, if the data is invalid
        #
        # @note The returned error message may contain PII unless {#sanitize_pii} has not been set.
        #
        # @see #valid?
        # @see #validate
        def validate_with_error_message(data)
          errors = validate(data)
          return if errors.empty?

          errors.each { |error| error.delete("data") } if sanitize_pii

          "Validation errors:\n\n#{errors.map { |e| ::JSON.pretty_generate(e) }.join("\n\n")}"
        end

        # Merges default values defined in the JSON schema into the given `data` without mutating it.
        #
        # @param data [Object] JSON data to populate with defaults from the schema
        # @return [Object] data updated with defaults for missing properties
        def merge_defaults(data)
          ::Marshal.load(::Marshal.dump(data)).tap do |deep_duped_data|
            defaulting_schema.valid?(deep_duped_data)
          end
        end

        private

        def defaulting_schema
          @defaulting_schema ||= begin
            config = schema.configuration.dup
            config.insert_property_defaults = true
            ::JSONSchemer.schema(schema.value, configuration: config)
          end
        end
      end
    end
  end
end
