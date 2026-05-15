# Copyright 2024 - 2026 Block, Inc.
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
      # @private
      module Param
        # @param hash_of_params [Hash{String => DynamicParam, StaticParam}] params keyed by name
        def self.dump_params_hash(hash_of_params)
          hash_of_params.sort_by(&:first).to_h { |name, param| [name, param.to_dumpable_hash(name)] }
        end

        # @param hash_of_hashes [Hash{String => Hash{String => Object}}] serialized params keyed by name
        def self.load_params_hash(hash_of_hashes)
          hash_of_hashes.to_h { |name, hash| [name, from_hash(hash, name)] }
        end

        # @param hash [Hash{String => Object}] serialized param data
        # @param name [String] param name, used as default source path for dynamic params
        def self.from_hash(hash, name)
          if hash.key?(StaticParam::VALUE)
            StaticParam.from_hash(hash)
          else
            DynamicParam.from_hash(hash, name)
          end
        end
      end

      # Represents metadata about dynamic params we pass to our update scripts.
      #
      # @private
      class DynamicParam < ::Data.define(:source_path, :cardinality)
        SOURCE_PATH = "source_path"
        CARDINALITY = "cardinality"

        # @param hash [Hash{String => Object}] serialized form of a DynamicParam
        # @param name [String] param name, used as default source path
        def self.from_hash(hash, name)
          new(
            source_path: hash[SOURCE_PATH] || name,
            cardinality: hash.fetch(CARDINALITY).to_sym
          )
        end

        # @param param_name [String] name of this param, used to omit redundant source path
        def to_dumpable_hash(param_name)
          {
            # Keys here are ordered alphabetically; please keep them that way.
            CARDINALITY => cardinality.to_s,
            SOURCE_PATH => (source_path if source_path != param_name)
          }
        end

        # @param event_or_prepared_record [Hash{String => Object}] event or prepared record to extract value from
        def value_for(event_or_prepared_record)
          case cardinality
          when :many then Support::HashUtil.fetch_leaf_values_at_path(event_or_prepared_record, source_path.split(".")) { [] }
          when :one then Support::HashUtil.fetch_value_at_path(event_or_prepared_record, source_path.split(".")) { nil }
          end
        end
      end

      # @private
      class StaticParam < ::Data.define(:value)
        VALUE = "value"

        # @param hash [Hash{String => Object}] serialized form of a StaticParam
        def self.from_hash(hash)
          new(value: hash.fetch(VALUE))
        end

        # @param param_name [String] name of this param (unused for static params, present for interface consistency)
        def to_dumpable_hash(param_name)
          {
            # Keys here are ordered alphabetically; please keep them that way.
            VALUE => value
          }
        end

        # @param event_or_prepared_record [Hash{String => Object}] event or prepared record (ignored; static value is always returned)
        def value_for(event_or_prepared_record)
          value
        end
      end
    end
  end
end
