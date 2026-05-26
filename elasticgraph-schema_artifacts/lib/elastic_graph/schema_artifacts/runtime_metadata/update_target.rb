# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/schema_artifacts/runtime_metadata/params"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Provides runtime metadata related to the targets of datastore `update` calls.
      #
      # @private
      class UpdateTarget < ::Data.define(
        :type,
        :relationship,
        :script_id,
        :id_source,
        :routing_value_source,
        :rollover_timestamp_value_source,
        :top_level_fields_params,
        :nested_sourced_fields_params,
        :nested_sourced_path_identifiers_params,
        :nested_sourced_paths,
        :metadata_params
      )
        TYPE = "type"
        RELATIONSHIP = "relationship"
        SCRIPT_ID = "script_id"
        ID_SOURCE = "id_source"
        ROUTING_VALUE_SOURCE = "routing_value_source"
        ROLLOVER_TIMESTAMP_VALUE_SOURCE = "rollover_timestamp_value_source"
        TOP_LEVEL_FIELDS_PARAMS = "top_level_fields_params"
        NESTED_SOURCED_FIELDS_PARAMS = "nested_sourced_fields_params"
        NESTED_SOURCED_PATH_IDENTIFIERS_PARAMS = "nested_sourced_path_identifiers_params"
        NESTED_SOURCED_PATHS = "nested_sourced_paths"
        METADATA_PARAMS = "metadata_params"

        def self.from_hash(hash)
          new(
            type: hash[TYPE],
            relationship: hash[RELATIONSHIP],
            script_id: hash[SCRIPT_ID],
            id_source: hash[ID_SOURCE],
            routing_value_source: hash[ROUTING_VALUE_SOURCE],
            rollover_timestamp_value_source: hash[ROLLOVER_TIMESTAMP_VALUE_SOURCE],
            top_level_fields_params: Param.load_params_hash(hash[TOP_LEVEL_FIELDS_PARAMS] || {}),
            nested_sourced_fields_params: Param.load_params_hash(hash[NESTED_SOURCED_FIELDS_PARAMS] || {}),
            nested_sourced_path_identifiers_params: Param.load_params_hash(hash[NESTED_SOURCED_PATH_IDENTIFIERS_PARAMS] || {}),
            nested_sourced_paths: hash[NESTED_SOURCED_PATHS] || {},
            metadata_params: Param.load_params_hash(hash[METADATA_PARAMS] || {})
          )
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            ID_SOURCE => id_source,
            METADATA_PARAMS => Param.dump_params_hash(metadata_params),
            NESTED_SOURCED_FIELDS_PARAMS => Param.dump_params_hash(nested_sourced_fields_params),
            NESTED_SOURCED_PATH_IDENTIFIERS_PARAMS => Param.dump_params_hash(nested_sourced_path_identifiers_params),
            NESTED_SOURCED_PATHS => nested_sourced_paths,
            RELATIONSHIP => relationship,
            ROLLOVER_TIMESTAMP_VALUE_SOURCE => rollover_timestamp_value_source,
            ROUTING_VALUE_SOURCE => routing_value_source,
            SCRIPT_ID => script_id,
            TOP_LEVEL_FIELDS_PARAMS => Param.dump_params_hash(top_level_fields_params),
            TYPE => type
          }
        end

        def for_normal_indexing?
          script_id == INDEX_DATA_UPDATE_SCRIPT_ID
        end

        def params_for(doc_id:, event:, prepared_record:)
          top_level_fields = top_level_fields_params.to_h do |name, param|
            [name, param.value_for(prepared_record)]
          end

          meta = metadata_params.to_h do |name, param|
            [name, param.value_for(event)]
          end

          nested_sourced_fields = nested_sourced_fields_params.to_h do |name, param|
            [name, param.value_for(prepared_record)]
          end

          nested_sourced_path_identifiers = nested_sourced_path_identifiers_params.to_h do |name, param|
            [name, param.value_for(prepared_record)]
          end

          meta.merge({
            "id" => doc_id,
            "topLevelFields" => top_level_fields,
            "nestedSourcedFields" => nested_sourced_fields,
            "nestedSourcedPathIdentifiers" => nested_sourced_path_identifiers,
            "nestedSourcedPaths" => nested_sourced_paths
          })
        end
      end
    end
  end
end
