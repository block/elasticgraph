# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/json_ingestion/schema_definition/indexing/field"
require "elastic_graph/schema_definition/indexing/field_reference"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        # Wraps an indexing field reference with JSON schema state needed when resolving fields.
        #
        # @api private
        class FieldReference < DelegateClass(ElasticGraph::SchemaDefinition::Indexing::FieldReference)
          # @dynamic __getobj__, json_schema_layers, json_schema_customizations, doc_comment
          # @return [Array<Symbol>] JSON schema wrapper layers from the field type reference
          attr_reader :json_schema_layers

          # @return [Hash<Symbol, Object>] user-defined JSON schema customizations
          attr_reader :json_schema_customizations

          # @return [String, nil] documentation for the referenced field
          attr_reader :doc_comment

          # @param field_reference [ElasticGraph::SchemaDefinition::Indexing::FieldReference] the field reference to wrap
          # @param json_schema_layers [Array<Symbol>] JSON schema wrapper layers from the field type reference
          # @param json_schema_customizations [Hash<Symbol, Object>] user-defined JSON schema customizations
          # @param doc_comment [String, nil] documentation for the referenced field
          def initialize(field_reference, json_schema_layers:, json_schema_customizations:, doc_comment:)
            super(field_reference)
            @json_schema_layers = json_schema_layers
            @json_schema_customizations = json_schema_customizations
            @doc_comment = doc_comment
          end

          # Resolves this reference to a JSON-schema-aware indexing field.
          #
          # @return [Field, nil] the resolved field, or nil when the type is unresolved
          def resolve
            return nil unless (resolved_field = super)

            Field.new(
              resolved_field,
              json_schema_layers: json_schema_layers,
              json_schema_customizations: json_schema_customizations,
              doc_comment: doc_comment
            )
          end

          # Compares field references, including JSON schema metadata tracked by this wrapper.
          #
          # @param other [Object] the object to compare against
          # @return [Boolean] true when the field reference and JSON schema metadata match
          def ==(other)
            case other
            when FieldReference
              __getobj__ == other.__getobj__ &&
                json_schema_layers == other.json_schema_layers &&
                json_schema_customizations == other.json_schema_customizations &&
                doc_comment == other.doc_comment
            else
              super
            end
          end

          def eql?(other)
            self == other
          end

          # Returns a hash code based on the wrapped field reference and JSON schema metadata.
          #
          # @return [Integer] the hash code
          def hash
            [__getobj__, json_schema_layers, json_schema_customizations, doc_comment].hash
          end
        end
      end
    end
  end
end
