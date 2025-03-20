# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Helper class that contains common logic for instantiating `UpdateTargets`.
      # @private
      module UpdateTargetFactory
        def self.new_normal_indexing_update_target(
          type:,
          relationship:,
          id_source:,
          data_params:,
          routing_value_source:,
          rollover_timestamp_value_source:
        )
          SchemaArtifacts::RuntimeMetadata::UpdateTarget.new(
            type: type,
            relationship: relationship,
            script_id: INDEX_DATA_UPDATE_SCRIPT_ID,
            id_source: id_source,
            metadata_params: standard_metadata_params.merge({
              "relationship" => SchemaArtifacts::RuntimeMetadata::StaticParam.new(value: relationship)
            }),
            data_params: data_params,
            routing_value_source: routing_value_source,
            rollover_timestamp_value_source: rollover_timestamp_value_source
          )
        end

        private_class_method def self.standard_metadata_params
          @standard_metadata_params ||= {
            "sourceId" => single_value_param_from("id"),
            "sourceType" => single_value_param_from("type"),
            "version" => single_value_param_from("version")
          }
        end

        private_class_method def self.single_value_param_from(source_path)
          SchemaArtifacts::RuntimeMetadata::DynamicParam.new(
            source_path: source_path,
            cardinality: :one
          )
        end
      end
    end
  end
end
