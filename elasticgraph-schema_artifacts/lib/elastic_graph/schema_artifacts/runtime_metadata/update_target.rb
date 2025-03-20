# Copyright 2024 - 2025 Block, Inc.
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
      class UpdateTarget < ::Data.define(
        :type,
        :relationship,
        :script_id,
        :id_source,
        :routing_value_source,
        :rollover_timestamp_value_source,
        :data_params,
        :metadata_params
      )
        TYPE = "type"
        RELATIONSHIP = "relationship"
        SCRIPT_ID = "script_id"
        ID_SOURCE = "id_source"
        ROUTING_VALUE_SOURCE = "routing_value_source"
        ROLLOVER_TIMESTAMP_VALUE_SOURCE = "rollover_timestamp_value_source"
        DATA_PARAMS = "data_params"
        METADATA_PARAMS = "metadata_params"

        def self.from_hash(hash)
          new(
            type: hash[TYPE],
            relationship: hash[RELATIONSHIP],
            script_id: hash[SCRIPT_ID],
            id_source: hash[ID_SOURCE],
            routing_value_source: hash[ROUTING_VALUE_SOURCE],
            rollover_timestamp_value_source: hash[ROLLOVER_TIMESTAMP_VALUE_SOURCE],
            data_params: Param.load_params_hash(hash[DATA_PARAMS] || {}),
            metadata_params: Param.load_params_hash(hash[METADATA_PARAMS] || {})
          )
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            DATA_PARAMS => Param.dump_params_hash(data_params),
            ID_SOURCE => id_source,
            METADATA_PARAMS => Param.dump_params_hash(metadata_params),
            RELATIONSHIP => relationship,
            ROLLOVER_TIMESTAMP_VALUE_SOURCE => rollover_timestamp_value_source,
            ROUTING_VALUE_SOURCE => routing_value_source,
            SCRIPT_ID => script_id,
            TYPE => type
          }
        end

        def for_normal_indexing?
          script_id == INDEX_DATA_UPDATE_SCRIPT_ID
        end

        def params_for(doc_id:, event:, prepared_record:)
          data = data_params.to_h do |name, param|
            [name, param.value_for(prepared_record)]
          end

          meta = metadata_params.to_h do |name, param|
            [name, param.value_for(event)]
          end

          meta.merge({"id" => doc_id, "data" => data})
        end
      end
    end
  end
end
