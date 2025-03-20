# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/hash_dumper"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      module Param
        def self.dump_params_hash(hash_of_params)
          hash_of_params.sort_by(&:first).to_h { |name, param| [name, param.to_dumpable_hash(name)] }
        end

        def self.load_params_hash(hash_of_hashes)
          hash_of_hashes.to_h { |name, hash| [name, from_hash(hash, name)] }
        end

        def self.from_hash(hash, name)
          if hash.key?(StaticParam::VALUE)
            StaticParam.from_hash(hash)
          else
            DynamicParam.from_hash(hash, name)
          end
        end
      end

      # Represents metadata about dynamic params we pass to our update scripts.
      class DynamicParam < ::Data.define(:source_path, :cardinality)
        SOURCE_PATH = "source_path"
        CARDINALITY = "cardinality"

        def self.from_hash(hash, name)
          new(
            source_path: hash[SOURCE_PATH] || name,
            cardinality: hash.fetch(CARDINALITY).to_sym
          )
        end

        def to_dumpable_hash(param_name)
          {
            # Keys here are ordered alphabetically; please keep them that way.
            CARDINALITY => cardinality.to_s,
            SOURCE_PATH => (source_path if source_path != param_name)
          }
        end

        def value_for(event_or_prepared_record)
          case cardinality
          when :many then Support::HashUtil.fetch_leaf_values_at_path(event_or_prepared_record, source_path) { [] }
          when :one then Support::HashUtil.fetch_value_at_path(event_or_prepared_record, source_path) { nil }
          end
        end
      end

      class StaticParam < ::Data.define(:value)
        VALUE = "value"

        def self.from_hash(hash)
          new(value: hash.fetch(VALUE))
        end

        def to_dumpable_hash(param_name)
          {
            # Keys here are ordered alphabetically; please keep them that way.
            VALUE => value
          }
        end

        def value_for(event_or_prepared_record)
          value
        end
      end
    end
  end
end
