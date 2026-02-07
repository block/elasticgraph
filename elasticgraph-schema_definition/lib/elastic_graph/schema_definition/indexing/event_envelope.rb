# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Contains logic related to "event envelope"--the layer of metadata that wraps all indexing events.
      #
      # @api private
      module EventEnvelope
        # @param indexed_type_names [Array<String>] names of the indexed types
        # @param json_schema_version [Integer] the version of the JSON schema
        # @return [Hash<String, Object>] the JSON schema for the ElasticGraph event envelope for the given `indexed_type_names`.
        def self.json_schema(indexed_type_names, json_schema_version)
          {
            "type" => "object",
            "description" => "Required by ElasticGraph to wrap every data event.",
            "properties" => {
              "op" => {
                "description" => "Indicates what type of operation the event represents. For now, only `upsert` is supported, but we plan to support other operations in the future.",
                "type" => "string",
                "enum" => %w[upsert]
              },
              "type" => {
                "description" => "The type of object present in `record`.",
                "type" => "string",
                # Sorting doesn't really matter here, but it's nice for the output in the schema artifact to be consistent.
                "enum" => indexed_type_names.sort
              },
              "id" => {
                "description" => "The unique identifier of the record.",
                "type" => "string",
                "maxLength" => DEFAULT_MAX_KEYWORD_LENGTH
              },
              "version" => {
                "description" => 'Used to handle duplicate and out-of-order events. When ElasticGraph ingests multiple events for the same `type` and `id`, the one with the largest `version` will "win".',
                "type" => "integer",
                "minimum" => 0,
                "maximum" => (2**63) - 1
              },
              "record" => {
                "description" => "The record of this event. The payload of this field must match the JSON schema of the named `type`.",
                "type" => "object"
              },
              "latency_timestamps" => {
                "description" => "Timestamps from which ElasticGraph measures indexing latency. The `ElasticGraphIndexingLatencies` log message produced for each event will include a measurement from each timestamp included in this map.",
                "type" => "object",
                "additionalProperties" => false,
                "patternProperties" => {
                  "description" => "A timestamp from which ElasticGraph will measure indexing latency. The timestamp name must end in `_at`.",
                  "^\\w+_at$" => {"type" => "string", "format" => "date-time"}
                }
              },
              JSON_SCHEMA_VERSION_KEY => {
                "description" => "The version of the JSON schema the publisher was using when the event was published. ElasticGraph will use the JSON schema matching this version to process the event.",
                "const" => json_schema_version
              },
              "message_id" => {
                "description" => "The optional ID of the message containing this event from whatever messaging system is being used between the publisher and the ElasticGraph indexer.",
                "type" => "string"
              },
              "skip_failure_categorization" => {
                "description" => "When true, ElasticGraph will skip checking if a failed event has been superseded by a newer version in the datastore. This is useful to avoid unnecessary datastore queries during normal indexing. When absent or false, the version check runs as usual.",
                "type" => "boolean"
              }
            },
            "additionalProperties" => false,
            "required" => ["op", "type", "id", "version", JSON_SCHEMA_VERSION_KEY],
            "if" => {
              "properties" => {
                "op" => {"const" => "upsert"}
              }
            },
            "then" => {"required" => ["record"]}
          }
        end
      end
    end
  end
end
