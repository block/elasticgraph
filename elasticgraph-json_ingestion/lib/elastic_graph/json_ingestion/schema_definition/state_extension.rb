# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      # Extension module applied to `ElasticGraph::SchemaDefinition::State` to support JSON ingestion state.
      #
      # @private
      module StateExtension
        # @dynamic json_schema_version, json_schema_version=
        # @dynamic json_schema_version_setter_location, json_schema_version_setter_location=
        # @dynamic allow_omitted_json_schema_fields, allow_omitted_json_schema_fields=
        # @dynamic allow_extra_json_schema_fields, allow_extra_json_schema_fields=
        attr_accessor :json_schema_version, :json_schema_version_setter_location, :allow_omitted_json_schema_fields, :allow_extra_json_schema_fields

        def self.extended(state)
          state.json_schema_version = nil
          state.json_schema_version_setter_location = nil
          state.allow_omitted_json_schema_fields = false
          state.allow_extra_json_schema_fields = true
        end
      end
    end
  end
end
