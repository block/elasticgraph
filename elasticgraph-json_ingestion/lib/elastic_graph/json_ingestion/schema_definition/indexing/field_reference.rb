# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/field"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        # @!parse class FieldReference < ::Data; end
        FieldReference = ::Data.define(
          :field_reference,
          :json_schema_layers,
          :json_schema_customizations
        )

        # A JSON-schema-aware wrapper around the core indexing field reference.
        #
        # @api private
        class FieldReference < ::Data
          # Resolves this field reference into a JSON-schema-aware field, or `nil` if unresolvable.
          #
          # @return [ElasticGraph::SchemaDefinition::Indexing::Field, nil]
          def resolve
            return nil unless (resolved_field = field_reference.resolve)

            json_schema_field = resolved_field.extend(Indexing::FieldExtension) # : ElasticGraph::SchemaDefinition::Indexing::Field & FieldExtension
            json_schema_field.with_json_schema(
              json_schema_layers: json_schema_layers,
              json_schema_customizations: json_schema_customizations
            )
          end

          # @dynamic initialize, with, field_reference, json_schema_layers, json_schema_customizations
        end
      end
    end
  end
end
