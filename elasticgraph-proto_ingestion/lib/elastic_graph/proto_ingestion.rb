# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  # Namespace for Protocol Buffers schema artifact generation extensions.
  module ProtoIngestion
    # The name of the generated Protocol Buffers schema file.
    PROTO_SCHEMA_FILE = "schema.proto"

    # The name of the generated proto field-number mapping file.
    PROTO_FIELD_NUMBERS_FILE = "proto_field_numbers.yaml"

    # Default protobuf options applied to ElasticGraph's built-in scalar types as they are constructed.
    BUILT_IN_SCALAR_PROTO_OPTIONS_BY_NAME = {
      "Boolean" => {type: "bool"},
      "Cursor" => {type: "string"},
      "Date" => {type: "string", field_comment: %(Must be formatted as an ISO 8601 date, e.g. "2024-11-25".)},
      "DateTime" => {type: "google.protobuf.Timestamp", import: "google/protobuf/timestamp.proto"},
      "Float" => {type: "double"},
      "ID" => {type: "string"},
      "Int" => {type: "int32"},
      "JsonSafeLong" => {type: "int64"},
      "LocalTime" => {type: "string", field_comment: %(Must be formatted as an ISO 8601 local time, e.g. "14:23:12".)},
      "LongString" => {type: "int64"},
      "String" => {type: "string"},
      "TimeZone" => {type: "string", field_comment: %(Must be an IANA time zone identifier, e.g. "America/Los_Angeles".)},
      "Untyped" => {type: "string"}
    }.freeze # : ::Hash[::String, {type: ::String, ?import: ::String, ?field_comment: ::String}]

    # The default ElasticGraph scalar for each protobuf type. Several built-in scalars share
    # a protobuf type, so select its default scalar before inverting the mapping.
    DEFAULT_SCALARS_BY_PROTO_TYPE = BUILT_IN_SCALAR_PROTO_OPTIONS_BY_NAME
      .slice("Boolean", "Float", "DateTime", "Int", "LongString", "String")
      .to_h { |name, options| [options.fetch(:type), name] }.freeze
  end
end
