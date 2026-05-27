# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/graphql/scalar_coercion_adapters/valid_time_zones"
require "elastic_graph/json_ingestion/schema_definition/factory_extension"
require "elastic_graph/json_ingestion/schema_definition/state_extension"

module ElasticGraph
  module JSONIngestion
    # Namespace for all JSON Schema schema definition support.
    #
    # {SchemaDefinition::APIExtension} is the primary entry point and should be used as a schema definition extension module.
    module SchemaDefinition
      # Module designed to be extended onto an {ElasticGraph::SchemaDefinition::API} instance
      # to add JSON Schema artifact generation capabilities.
      module APIExtension
        # Default JSON schema options applied to ElasticGraph's built-in scalar types when this extension
        # is loaded. Keyed by the un-overridden type name; the lookup at runtime maps each key through
        # `type_name_overrides` so renamed built-ins still receive the right options.
        BUILT_IN_SCALAR_JSON_SCHEMA_OPTIONS_BY_NAME = {
          "Boolean" => {type: "boolean"},
          "Float" => {type: "number"},
          "ID" => {type: "string"},
          "Int" => {type: "integer", minimum: INT_MIN, maximum: INT_MAX},
          "String" => {type: "string"},
          "Cursor" => {type: "string"},
          "Date" => {type: "string", format: "date"},
          "DateTime" => {type: "string", format: "date-time"},
          "LocalTime" => {type: "string", pattern: VALID_LOCAL_TIME_JSON_SCHEMA_PATTERN},
          "TimeZone" => {type: "string", enum: GraphQL::ScalarCoercionAdapters::VALID_TIME_ZONES.to_a.freeze},
          "Untyped" => {type: ["array", "boolean", "integer", "number", "object", "string"].freeze},
          "JsonSafeLong" => {type: "integer", minimum: JSON_SAFE_LONG_MIN, maximum: JSON_SAFE_LONG_MAX},
          "LongString" => {type: "integer", minimum: LONG_STRING_MIN, maximum: LONG_STRING_MAX}
        }.freeze

        # Wires up the JSON ingestion extensions when this module is extended onto an API instance.
        #
        # @param api [ElasticGraph::SchemaDefinition::API] the API instance to extend
        # @return [void]
        # @api private
        def self.extended(api)
          state = api.state.extend(StateExtension) # : ElasticGraph::SchemaDefinition::State & StateExtension
          state.reserved_type_names << EVENT_ENVELOPE_JSON_SCHEMA_NAME
          api.factory.extend FactoryExtension

          # Build a lookup from final (post-`type_name_overrides`) names to JSON schema options. We can't
          # key directly on `type.name` because users may have overridden the names of built-in scalars
          # (e.g. `Cursor` → `PreCursor`); the keys in `BUILT_IN_SCALAR_JSON_SCHEMA_OPTIONS_BY_NAME` are
          # always the un-overridden names.
          options_by_final_name = BUILT_IN_SCALAR_JSON_SCHEMA_OPTIONS_BY_NAME.to_h do |name, options|
            [api.state.type_ref(name).to_final_form.name, options]
          end

          api.on_built_in_types do |type|
            if (options = options_by_final_name[type.name])
              scalar_type = type # : ElasticGraph::SchemaDefinition::SchemaElements::ScalarType & SchemaElements::ScalarTypeExtension
              scalar_type.json_schema(**options)
            elsif type.name == api.state.type_ref("GeoLocation").to_final_form.name
              # @type var geo_location_type: ElasticGraph::SchemaDefinition::SchemaElements::TypeWithSubfields & SchemaElements::ObjectInterfaceExtension
              geo_location_type = _ = type
              names = api.state.schema_elements

              # We use `nullable: false` because `GeoLocation` is indexed as a single `geo_point` field,
              # and therefore can't support a `latitude` without a `longitude` or vice-versa.
              latitude = geo_location_type.graphql_fields_by_name.fetch(names.latitude) # : ElasticGraph::SchemaDefinition::SchemaElements::Field & SchemaElements::FieldExtension
              longitude = geo_location_type.graphql_fields_by_name.fetch(names.longitude) # : ElasticGraph::SchemaDefinition::SchemaElements::Field & SchemaElements::FieldExtension
              latitude.json_schema minimum: -90, maximum: 90, nullable: false
              longitude.json_schema minimum: -180, maximum: 180, nullable: false
            end
          end
        end

        # Defines the version number of the current JSON schema. Importantly, every time a change is made that impacts the JSON schema
        # artifact, the version number must be incremented to ensure that each different version of the JSON schema is identified by a unique
        # version number. The publisher will then include this version number in published events to identify the version of the schema it
        # was using. This avoids the need to deploy the publisher and ElasticGraph indexer at the same time to keep them in sync.
        #
        # @note While this is an important part of how ElasticGraph is designed to support schema evolution, it can be annoying to constantly
        #   have to increment this while rapidly changing the schema during prototyping. You can disable the requirement to increment this
        #   on every JSON schema change with {#enforce_json_schema_version}.
        #
        # @param version [Integer] current version number of the JSON schema artifact
        # @return [void]
        # @see #enforce_json_schema_version
        def json_schema_version(version)
          state = json_ingestion_state

          if !version.is_a?(Integer) || version < 1
            raise Errors::SchemaError, "`json_schema_version` must be a positive integer. Specified version: #{version}"
          end

          if state.json_schema_version
            raise Errors::SchemaError, "`json_schema_version` can only be set once on a schema. Previously-set version: #{state.json_schema_version}"
          end

          state.json_schema_version = version
          state.json_schema_version_setter_location = caller_locations(1, 1).to_a.first
          nil
        end

        # Configures whether JSON schema artifact dumping enforces the requirement that the JSON schema version is incremented every time
        # dumping the JSON schemas results in a changed artifact. Defaults to `true`.
        #
        # @note Generally speaking, you will want this to be `true` for any ElasticGraph application that is in
        #    production as the versioning of JSON schemas is what supports safe schema evolution as it allows
        #    ElasticGraph to identify which version of the JSON schema the publishing system was operating on
        #    when it published an event.
        #
        #    It can be useful to set it to `false` before your application is in production, as you do not want
        #    to be forced to bump the version after every single schema change while you are building an initial
        #    prototype.
        #
        # @param value [Boolean] whether to require `json_schema_version` to be incremented on changes that impact `json_schemas.yaml`
        # @return [void]
        # @see #json_schema_version
        #
        # @example Disable enforcement during initial prototyping
        #   ElasticGraph.define_schema do |schema|
        #     # TODO: remove this once we're past the prototyping stage
        #     schema.enforce_json_schema_version false
        #   end
        def enforce_json_schema_version(value)
          unless value == true || value == false
            raise Errors::SchemaError, "`enforce_json_schema_version` must be a boolean. Specified value: #{value.inspect}"
          end

          json_ingestion_state.enforce_json_schema_version = value
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
          state = json_ingestion_state

          unless [true, false].include?(allow_omitted_fields)
            raise Errors::SchemaError, "`allow_omitted_fields` must be true or false"
          end

          unless [true, false].include?(allow_extra_fields)
            raise Errors::SchemaError, "`allow_extra_fields` must be true or false"
          end

          state.allow_omitted_json_schema_fields = allow_omitted_fields
          state.allow_extra_json_schema_fields = allow_extra_fields
          nil
        end

        private

        # Returns the API's `state` narrowed to include this gem's `StateExtension`. Centralizes
        # the Steep cast that's needed because Steep can't see the `extend(StateExtension)` applied
        # at runtime in `extended`.
        def json_ingestion_state
          state # : ElasticGraph::SchemaDefinition::State & StateExtension
        end
      end
    end
  end
end
