# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/field_type/object_extension"
require "elastic_graph/schema_definition/indexing/field_type/object"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        module FieldType
          # JSON-ingestion indexing field type wrapper for objects.
          #
          # @private
          class Object
            include ObjectExtension

            def self.wrap(field_type, json_schema_options:)
              new(field_type).with_json_schema_options(json_schema_options)
            end

            def initialize(field_type)
              @field_type = field_type
            end

            def schema_def_state
              @field_type.schema_def_state
            end

            def type_name
              @field_type.type_name
            end

            def subfields
              @field_type.subfields
            end

            def mapping_options
              @field_type.mapping_options
            end

            def doc_comment
              @field_type.doc_comment
            end

            def to_mapping
              @field_type.to_mapping
            end
          end
        end
      end
    end
  end
end
