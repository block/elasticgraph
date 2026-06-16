# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/deprecated_element"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Extension module applied to `ElasticGraph::SchemaDefinition::State` to support JSON ingestion state.
      #
      # @private
      module StateExtension
        # @dynamic json_schema_version, json_schema_version=
        # @dynamic json_schema_version_setter_location, json_schema_version_setter_location=
        # @dynamic enforce_json_schema_version, enforce_json_schema_version=
        # @dynamic allow_omitted_json_schema_fields, allow_omitted_json_schema_fields=
        # @dynamic allow_extra_json_schema_fields, allow_extra_json_schema_fields=
        # @dynamic renamed_types_by_old_name, renamed_types_by_old_name=
        # @dynamic deleted_types_by_old_name, deleted_types_by_old_name=
        # @dynamic renamed_fields_by_type_name_and_old_field_name, renamed_fields_by_type_name_and_old_field_name=
        # @dynamic deleted_fields_by_type_name_and_old_field_name, deleted_fields_by_type_name_and_old_field_name=
        attr_accessor :json_schema_version, :json_schema_version_setter_location, :enforce_json_schema_version, :allow_omitted_json_schema_fields, :allow_extra_json_schema_fields,
          :renamed_types_by_old_name, :deleted_types_by_old_name, :renamed_fields_by_type_name_and_old_field_name, :deleted_fields_by_type_name_and_old_field_name

        def self.extended(state)
          state.json_schema_version = nil
          state.json_schema_version_setter_location = nil
          state.enforce_json_schema_version = true
          state.allow_omitted_json_schema_fields = false
          state.allow_extra_json_schema_fields = true
          state.renamed_types_by_old_name = {}
          state.deleted_types_by_old_name = {}
          state.renamed_fields_by_type_name_and_old_field_name = ::Hash.new { |h, k| h[k] = {} }
          state.deleted_fields_by_type_name_and_old_field_name = ::Hash.new { |h, k| h[k] = {} }
        end

        def register_renamed_type(type_name, from:, defined_at:, defined_via:)
          renamed_types_by_old_name[from] = DeprecatedElement.new(
            schema_def_state: self,
            name: type_name,
            defined_at: defined_at,
            defined_via: defined_via
          )
        end

        def register_deleted_type(type_name, defined_at:, defined_via:)
          deleted_types_by_old_name[type_name] = DeprecatedElement.new(
            schema_def_state: self,
            name: type_name,
            defined_at: defined_at,
            defined_via: defined_via
          )
        end

        def register_renamed_field(type_name, from:, to:, defined_at:, defined_via:)
          renamed_fields_by_old_field_name = renamed_fields_by_type_name_and_old_field_name[type_name]
          renamed_fields_by_old_field_name[from] = DeprecatedElement.new(
            schema_def_state: self,
            name: to,
            defined_at: defined_at,
            defined_via: defined_via
          )
        end

        def register_deleted_field(type_name, field_name, defined_at:, defined_via:)
          deleted_fields_by_old_field_name = deleted_fields_by_type_name_and_old_field_name[type_name]
          deleted_fields_by_old_field_name[field_name] = DeprecatedElement.new(
            schema_def_state: self,
            name: field_name,
            defined_at: defined_at,
            defined_via: defined_via
          )
        end
      end
    end
  end
end
