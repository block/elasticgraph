# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/hash_dumper"
require "elastic_graph/schema_artifacts/runtime_metadata/index_field"
require "elastic_graph/schema_artifacts/runtime_metadata/sort_field"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Runtime metadata related to a datastore index definition.
      #
      # @private
      class IndexDefinition < ::Data.define(:route_with, :rollover, :default_sort_fields, :current_sources, :fields_by_path)
        ROUTE_WITH = "route_with"
        ROLLOVER = "rollover"
        DEFAULT_SORT_FIELDS = "default_sort_fields"
        CURRENT_SOURCES = "current_sources"
        FIELDS_BY_PATH = "fields_by_path"

        def initialize(route_with:, rollover:, default_sort_fields:, current_sources:, fields_by_path:)
          super(
            route_with: route_with,
            rollover: rollover,
            default_sort_fields: default_sort_fields,
            current_sources: current_sources.to_set,
            fields_by_path: fields_by_path
          )
        end

        def self.from_hash(hash)
          new(
            route_with: hash[ROUTE_WITH],
            rollover: hash[ROLLOVER]&.then { |h| Rollover.from_hash(h) },
            default_sort_fields: hash[DEFAULT_SORT_FIELDS]&.map { |h| SortField.from_hash(h) } || [],
            current_sources: hash[CURRENT_SOURCES] || [],
            fields_by_path: (hash[FIELDS_BY_PATH] || {}).transform_values { |h| IndexField.from_hash(h) }
          )
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            CURRENT_SOURCES => current_sources.sort,
            DEFAULT_SORT_FIELDS => default_sort_fields.map(&:to_dumpable_hash),
            FIELDS_BY_PATH => HashDumper.dump_hash(fields_by_path, &:to_dumpable_hash),
            ROLLOVER => rollover&.to_dumpable_hash,
            ROUTE_WITH => route_with
          }
        end

        # @private
        class Rollover < ::Data.define(:frequency, :timestamp_field_path)
          FREQUENCY = "frequency"
          TIMESTAMP_FIELD_PATH = "timestamp_field_path"

          # @implements Rollover
          def self.from_hash(hash)
            new(
              frequency: hash.fetch(FREQUENCY).to_sym,
              timestamp_field_path: hash[TIMESTAMP_FIELD_PATH]
            )
          end

          def to_dumpable_hash
            {
              # Keys here are ordered alphabetically; please keep them that way.
              FREQUENCY => frequency.to_s,
              TIMESTAMP_FIELD_PATH => timestamp_field_path
            }
          end
        end
      end
    end
  end
end
