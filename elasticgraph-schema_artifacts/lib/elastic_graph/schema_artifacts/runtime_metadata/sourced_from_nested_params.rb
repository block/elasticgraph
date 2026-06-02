# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/params"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Bundles the param configuration for nested sourced_from update targets.
      # `field_params` defines which fields to extract from the event and write onto
      # the target nested element. `path_identifier_params` defines which values to
      # extract from the event to identify which nested element to target.
      #
      # @private
      class SourcedFromNestedParams < ::Data.define(:field_params, :path_identifier_params)
        FIELD_PARAMS = "field_params"
        PATH_IDENTIFIER_PARAMS = "path_identifier_params"

        EMPTY = new(field_params: {}, path_identifier_params: {})

        def self.from_hash(hash)
          new(
            field_params: Param.load_params_hash(hash[FIELD_PARAMS] || {}),
            path_identifier_params: Param.load_params_hash(hash[PATH_IDENTIFIER_PARAMS] || {})
          )
        end

        def to_dumpable_hash
          {
            FIELD_PARAMS => Param.dump_params_hash(field_params),
            PATH_IDENTIFIER_PARAMS => Param.dump_params_hash(path_identifier_params)
          }
        end

        # Resolves params into script-ready values from the given prepared record.
        def script_params_for(prepared_record)
          {
            "sourcedFromNestedFields" => field_params.transform_values { |param| param.value_for(prepared_record) },
            "sourcedFromNestedPathIdentifiers" => path_identifier_params.transform_values { |param| param.value_for(prepared_record) }
          }
        end
      end
    end
  end
end
