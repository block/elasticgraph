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

          # Registers the name of a field that existed in a prior JSON schema version but has been deleted.
          #
          # @note In situations where this API applies, ElasticGraph will give you an error message indicating that you need to use this API
          #   or {FieldExtension#renamed_from}. Likewise, when ElasticGraph no longer needs to know about this, it'll give you a warning
          #   indicating the call to this method can be removed.
          #
          # @param field_name [String] name of field that used to exist but has been deleted
          # @return [void]
          #
          # @example Indicate that `Widget.description` has been deleted
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Widget" do |t|
          #       t.deleted_field "description"
          #     end
          #   end
          def deleted_field(field_name)
            json_ingestion_state.register_deleted_field(
              name,
              field_name,
              defined_at: caller_locations(2, 1).to_a.first, # : ::Thread::Backtrace::Location
              defined_via: %(type.deleted_field "#{field_name}")
            )
          end

          # Registers an old name that this type used to have in a prior JSON schema version.
          #
          # @note In situations where this API applies, ElasticGraph will give you an error message indicating that you need to use this API
          #   or {APIExtension#deleted_type}. Likewise, when ElasticGraph no longer needs to know about this, it'll give you a warning
          #   indicating the call to this method can be removed.
          #
          # @param old_name [String] old name this type used to have in a prior version of the schema
          # @return [void]
          #
          # @example Indicate that `Widget` used to be called `Component`.
          #   ElasticGraph.define_schema do |schema|
          #     schema.object_type "Widget" do |t|
          #       t.renamed_from "Component"
          #     end
          #   end
          def renamed_from(old_name)
            json_ingestion_state.register_renamed_type(
              name,
              from: old_name,
              defined_at: caller_locations(2, 1).to_a.first, # : ::Thread::Backtrace::Location
              defined_via: %(type.renamed_from "#{old_name}")
            )
          end

          # @private
          def to_indexing_field_type
            field_type = super # : Indexing::FieldType::Object
            field_type.json_schema_options = json_schema_options
            field_type.doc_comment = doc_comment
            field_type
          end

          private

          def json_ingestion_state
            extension_state = schema_def_state # : ::ElasticGraph::SchemaDefinition::State & SchemaDefinition::StateExtension
            extension_state.json_ingestion_state
          end
        end
      end
    end
  end
end
