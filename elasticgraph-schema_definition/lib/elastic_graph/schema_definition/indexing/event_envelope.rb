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
            "properties" => {
              "op" => {
                "type" => "string",
                "enum" => %w[upsert]
              },
              "type" => {
                "type" => "string",
                # Sorting doesn't really matter here, but it's nice for the output in the schema artifact to be consistent.
                "enum" => indexed_type_names.sort
              },
              "id" => {
                "type" => "string",
                "maxLength" => DEFAULT_MAX_KEYWORD_LENGTH
              },
              "version" => {
                "type" => "integer",
                "minimum" => 0,
                "maximum" => (2**63) - 1
              },
              "record" => {
                "type" => "object"
              },
              "latency_timestamps" => {
                "type" => "object",
                "additionalProperties" => false,
                "patternProperties" => {
                  "^\\w+_at$" => {"type" => "string", "format" => "date-time"}
                }
              },
              JSON_SCHEMA_VERSION_KEY => {
                "const" => json_schema_version
              },
              "message_id" => {
                "type" => "string",
                "description" => "The optional ID of the message containing this event from whatever messaging system is being used between the publisher and the ElasticGraph indexer."
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
