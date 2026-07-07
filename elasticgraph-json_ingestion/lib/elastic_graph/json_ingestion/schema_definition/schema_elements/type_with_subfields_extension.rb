# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/schema_elements/has_json_schema"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module SchemaElements
        # Extends object and interface type internals with JSON schema behavior.
        module TypeWithSubfieldsExtension
          include HasJSONSchema

          # @private
          def to_indexing_field_type
            field_type = super # : Indexing::FieldType::Object
            field_type.json_schema_options = json_schema_options
            field_type.doc_comment = doc_comment
            field_type
          end
        end
      end
    end
  end
end
