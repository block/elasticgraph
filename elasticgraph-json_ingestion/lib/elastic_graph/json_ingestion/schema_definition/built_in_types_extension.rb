# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql/scalar_coercion_adapters/valid_time_zones"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Extends ElasticGraph's built-in types with JSON ingestion configuration.
      module BuiltInTypesExtension
        # JSON Schema defaults applied to ElasticGraph's built-in scalar types.
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

        private

        def register_standard_elastic_graph_types
          super

          geo_location = schema_def_state.object_types_by_name.fetch(schema_def_state.type_ref("GeoLocation").to_final_form.name)

          # We use `nullable: false` because `GeoLocation` is indexed as a single `geo_point` field,
          # and therefore can't support a `latitude` without a `longitude` or vice-versa.
          geo_location.graphql_fields_by_name.fetch(names.latitude).json_schema minimum: -90, maximum: 90, nullable: false
          geo_location.graphql_fields_by_name.fetch(names.longitude).json_schema minimum: -180, maximum: 180, nullable: false
        end
      end
    end
  end
end
