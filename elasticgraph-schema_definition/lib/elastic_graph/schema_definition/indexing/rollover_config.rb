# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/index_definition"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # @private
      class RolloverConfig < ::Data.define(:frequency, :timestamp_field_path)
        def runtime_metadata
          SchemaArtifacts::RuntimeMetadata::IndexDefinition::Rollover.new(
            frequency: frequency,
            timestamp_field_path: timestamp_field_path.path_in_index
          )
        end
      end
    end
  end
end
