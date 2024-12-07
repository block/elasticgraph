# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_schema/validator"
require "json_schemer"

module ElasticGraph
  module JSONSchema
    # Factory class responsible for creating {Validator}s for particular ElasticGraph types.
    class ValidatorFactory
      # @dynamic root_schema
      # @private
      attr_reader :root_schema

      # @param schema [Hash<String, Object>] the JSON schema for an entire ElasticGraph schema
      # @param sanitize_pii [Boolean] whether to omit data that may contain PII from error messages
      def initialize(schema:, sanitize_pii:)
        @raw_schema = schema
        @root_schema = ::JSONSchemer.schema(
          schema,
          meta_schema: schema.fetch("$schema"),
          # Here we opt to have regular expressions resolved using an ecmo-compatible resolver, instead of Ruby's.
          #
          # We do this because regexp patterns in our JSON schema are intended to be used by JSON schema libraries
          # in many languages, not just in Ruby, and we want to support the widest compatibility. For example,
          # Ruby requires that we use `\A` and `\z` to anchor the start and end of the string (`^` and `$` anchor the
          # start and end of a line instead), where as ecmo regexes treat `^` and `$` as the start and end of the string.
          # For a pattern to be usable by non-Ruby publishers, we need to use `^/`$` for our start/end anchors, and we
          # want our validator to treat it the same way here.
          #
          # Also, this was the default before json_schemer 1.0 (and we used 0.x versions for a long time...).
          # This maintains the historical behavior we've had.
          #
          # For more info:
          # https://github.com/davishmcclurg/json_schemer/blob/v1.0.0/CHANGELOG.md#breaking-changes
          regexp_resolver: "ecma"
        )

        @sanitize_pii = sanitize_pii
        @validators_by_type_name = ::Hash.new do |hash, key|
          hash[key] = Validator.new(
            schema: root_schema.ref("#/$defs/#{key}"),
            sanitize_pii: sanitize_pii
          )
        end
      end

      # Gets the {Validator} for a particular ElasticGraph type.
      #
      # @param type_name [String] name of an ElasticGraph type
      # @return [Validator]
      def validator_for(type_name)
        @validators_by_type_name[type_name] # : Validator
      end

      # Returns a new factory configured to disallow unknown properties. By default, JSON schema
      # allows unknown properties (they'll simply be ignored when validating a JSON document). It
      # can be useful to validate more strictly, so that a document with properties not defined in
      # the JSON schema gets validation errors.
      #
      # @param except [Array<String>] paths under which unknown properties should still be allowed
      # @return [ValidatorFactory]
      def with_unknown_properties_disallowed(except: [])
        allow_paths = except.map { |p| p.split(".") }
        schema_copy = ::Marshal.load(::Marshal.dump(@raw_schema)) # deep copy so our mutations don't affect caller
        prevent_unknown_properties!(schema_copy, allow_paths: allow_paths)

        ValidatorFactory.new(schema: schema_copy, sanitize_pii: @sanitize_pii)
      end

      private

      # The meta schema allows additionalProperties in nearly every place. While a JSON schema definition
      # with additional properties is considered valid, we do not intend to use any additional properties,
      # and any usage of an additional property is almost certainly a typo. So here we mutate the meta
      # schema to set `additionalProperties: false` everywhere.
      def prevent_unknown_properties!(object, allow_paths:, parent_path: [])
        case object
        when ::Array
          object.each { |value| prevent_unknown_properties!(value, allow_paths: allow_paths, parent_path: parent_path) }
        when ::Hash
          if object["properties"]
            object["additionalProperties"] = false

            allowed_extra_props = allow_paths.filter_map do |path|
              *prefix, prop_name = path
              prop_name if prefix == parent_path
            end

            allowed_extra_props.each_with_object(object["properties"]) do |prop_name, props|
              # @type var empty_hash: ::Hash[::String, untyped]
              empty_hash = {}
              props[prop_name] ||= empty_hash
            end

            object["properties"].each do |key, value|
              prevent_unknown_properties!(value, allow_paths: allow_paths, parent_path: parent_path + [key])
            end
          else
            object.each do |key, value|
              prevent_unknown_properties!(value, allow_paths: allow_paths, parent_path: parent_path)
            end
          end
        end
      end
    end
  end
end
