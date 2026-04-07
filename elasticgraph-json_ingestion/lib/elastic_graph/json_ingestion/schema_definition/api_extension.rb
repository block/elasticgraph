# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/json_ingestion/schema_definition/factory_extension"

module ElasticGraph
  module JSONIngestion
    # Namespace for all JSON Schema schema definition support.
    #
    # {SchemaDefinition::APIExtension} is the primary entry point and should be used as a schema definition extension module.
    module SchemaDefinition
      # Module designed to be extended onto an {ElasticGraph::SchemaDefinition::API} instance
      # to add JSON Schema ingestion serializer capabilities. Higher-level schema-definition
      # entry points use it by default for backward compatibility, but it can also be explicitly passed in
      # `schema_definition_ingestion_serializer_extension_modules` when defining your {ElasticGraph::Local::RakeTasks}.
      module APIExtension
        # Wires up the factory extension when this module is extended onto an API instance.
        #
        # @param api [ElasticGraph::SchemaDefinition::API] the API instance to extend
        # @return [void]
        # @api private
        def self.extended(api)
          api.instance_variable_get(:@state).ingestion_serializer_state.tap do |state|
            state[:allow_omitted_json_schema_fields] = false unless state.key?(:allow_omitted_json_schema_fields)
            state[:allow_extra_json_schema_fields] = true unless state.key?(:allow_extra_json_schema_fields)
            state[:reserved_type_names] = (state[:reserved_type_names] || ::Set.new).merge([EVENT_ENVELOPE_JSON_SCHEMA_NAME])
          end

          api.factory.extend FactoryExtension
        end

        # Defines the version number of the current JSON schema. Importantly, every time a change is made that impacts the JSON schema
        # artifact, the version number must be incremented to ensure that each different version of the JSON schema is identified by a unique
        # version number. The publisher will then include this version number in published events to identify the version of the schema it
        # was using. This avoids the need to deploy the publisher and ElasticGraph indexer at the same time to keep them in sync.
        #
        # @note While this is an important part of how ElasticGraph is designed to support schema evolution, it can be annoying constantly
        #   have to increment this while rapidly changing the schema during prototyping. You can disable the requirement to increment this
        #   on every JSON schema change by setting `enforce_json_schema_version` to `false` in your `Rakefile`.
        #
        # @param version [Integer] current version number of the JSON schema artifact
        # @return [void]
        # @see Local::RakeTasks#enforce_json_schema_version
        def json_schema_version(version)
          if !version.is_a?(Integer) || version < 1
            raise Errors::SchemaError, "`json_schema_version` must be a positive integer. Specified version: #{version}"
          end

          if @state.ingestion_serializer_state[:json_schema_version]
            raise Errors::SchemaError, "`json_schema_version` can only be set once on a schema. Previously-set version: #{@state.ingestion_serializer_state[:json_schema_version]}"
          end

          @state.ingestion_serializer_state[:json_schema_version] = version
          @state.ingestion_serializer_state[:json_schema_version_setter_location] = caller_locations(1, 1).to_a.first
          nil
        end

        # Defines strictness of the JSON schema validation. By default, the JSON schema will require all fields to be provided by the
        # publisher (but they can be nullable) and will ignore extra fields that are not defined in the schema. Use this method to
        # configure this behavior.
        #
        # @param allow_omitted_fields [bool] Whether nullable fields can be omitted from indexing events.
        # @param allow_extra_fields [bool] Whether extra fields (e.g. beyond fields defined in the schema) can be included in indexing events.
        # @return [void]
        #
        # @note If you allow both omitted fields and extra fields, ElasticGraph's JSON schema validation will allow (and ignore) misspelled
        #   field names in indexing events. For example, if the ElasticGraph schema has a nullable field named `parentId` but the publisher
        #   accidentally provides it as `parent_id`, ElasticGraph would happily ignore the `parent_id` field entirely, because `parentId`
        #   is allowed to be omitted and `parent_id` would be treated as an extra field. Therefore, we recommend that you only set one of
        #   these to `true` (or none).
        def json_schema_strictness(allow_omitted_fields: false, allow_extra_fields: true)
          unless [true, false].include?(allow_omitted_fields)
            raise Errors::SchemaError, "`allow_omitted_fields` must be true or false"
          end

          unless [true, false].include?(allow_extra_fields)
            raise Errors::SchemaError, "`allow_extra_fields` must be true or false"
          end

          @state.ingestion_serializer_state[:allow_omitted_json_schema_fields] = allow_omitted_fields
          @state.ingestion_serializer_state[:allow_extra_json_schema_fields] = allow_extra_fields
          nil
        end
      end
    end
  end
end
