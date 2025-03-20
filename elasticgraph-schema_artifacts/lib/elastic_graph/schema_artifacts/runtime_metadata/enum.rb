# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/hash_dumper"
require "elastic_graph/schema_artifacts/runtime_metadata/sort_field"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      module Enum
        # Runtime metadata related to an ElasticGraph enum type.
        class Type < ::Data.define(:values_by_name)
          VALUES_BY_NAME = "values_by_name"

          def self.from_hash(hash)
            values_by_name = hash[VALUES_BY_NAME]&.transform_values do |value_hash|
              Value.from_hash(value_hash)
            end || {}

            new(values_by_name: values_by_name)
          end

          def to_dumpable_hash
            {
              # Keys here are ordered alphabetically; please keep them that way.
              VALUES_BY_NAME => HashDumper.dump_hash(values_by_name, &:to_dumpable_hash)
            }
          end
        end

        # Runtime metadata related to an ElasticGraph enum value.
        class Value < ::Data.define(:sort_field, :datastore_value, :datastore_abbreviation, :alternate_original_name)
          DATASTORE_VALUE = "datastore_value"
          DATASTORE_ABBREVIATION = "datastore_abbreviation"
          SORT_FIELD = "sort_field"
          ALTERNATE_ORIGINAL_NAME = "alternate_original_name"

          def self.from_hash(hash)
            new(
              sort_field: hash[SORT_FIELD]&.then { |h| SortField.from_hash(h) },
              datastore_value: hash[DATASTORE_VALUE],
              datastore_abbreviation: hash[DATASTORE_ABBREVIATION]&.to_sym,
              alternate_original_name: hash[ALTERNATE_ORIGINAL_NAME]
            )
          end

          def to_dumpable_hash
            {
              # Keys here are ordered alphabetically; please keep them that way.
              DATASTORE_ABBREVIATION => datastore_abbreviation&.to_s,
              DATASTORE_VALUE => datastore_value,
              ALTERNATE_ORIGINAL_NAME => alternate_original_name,
              SORT_FIELD => sort_field&.to_dumpable_hash
            }
          end
        end
      end
    end
  end
end
