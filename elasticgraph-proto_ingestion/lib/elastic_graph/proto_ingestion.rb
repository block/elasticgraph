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

    # The scalar the indexer ingests a protobuf field of each wire type as when runtime metadata
    # does not name one.
    DEFAULT_SCALARS_BY_PROTO_TYPE = {
      "bool" => "Boolean",
      "double" => "Float",
      "google.protobuf.Timestamp" => "DateTime",
      "int32" => "Int",
      "int64" => "LongString",
      "string" => "String"
    }.freeze

    # Built-in scalars whose valid values are narrower than their protobuf wire type allows.
    VALIDATED_SCALARS = %w[Boolean Date DateTime Float Int JsonSafeLong LocalTime LongString TimeZone].freeze
  end
end
