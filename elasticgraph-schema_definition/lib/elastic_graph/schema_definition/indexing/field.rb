# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/schema_definition/indexing/list_counts_mapping"
require "elastic_graph/support/hash_util"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Represents a field in a JSON document during indexing.
      #
      # @api private
      class Field < Support::MemoizableData.define(
        :name,
        :name_in_index,
        :type,
        :indexing_field_type,
        :accuracy_confidence,
        :mapping_customizations,
        :source,
        :runtime_field_script,
        :doc_comment
      )
        # @return [Hash<String, Object>] the mapping for this field. The returned hash should be composed entirely
        #   of Ruby primitives that, when converted to a JSON string, match the structure required by
        #   [Elasticsearch](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html).
        def mapping
          @mapping ||= begin
            raw_mapping = indexing_field_type
              .to_mapping
              .merge(Support::HashUtil.stringify_keys(mapping_customizations))

            if (object_type = type.fully_unwrapped.as_object_type) && type.list? && mapping_customizations[:type] == "nested"
              # If it's an object list field using the `nested` type, we need to add a `__counts` field to
              # the mapping for all of its subfields which are lists.
              ListCountsMapping.merged_into(raw_mapping, for_type: object_type)
            else
              raw_mapping
            end
          end
        end

        # Builds a hash containing the mapping for the provided fields, normalizing it in the same way that the
        # datastore does so that consistency checks between our index configuration and what's in the datastore
        # work properly.
        #
        # @param fields [Array<Field>] fields to generate a mapping hash from
        # @return [Hash<String, Object>] generated mapping hash
        def self.normalized_mapping_hash_for(fields)
          # When an object field has `properties`, the datastore normalizes the mapping by dropping
          # the `type => object` (it's implicit, as `properties` are only valid on an object...).
          # OTOH, when there are no properties, the datastore normalizes the mapping by dropping the
          # empty `properties` entry and instead returning `type => object`.
          return {"type" => "object"} if fields.empty?

          # Partition the fields into runtime fields and normal fields based on the presence of runtime_script
          runtime_fields, normal_fields = fields.partition(&:runtime_field_script)

          mapping_hash = {
            "properties" => normal_fields.to_h { |f| [f.name_in_index, f.mapping] }
          }
          unless runtime_fields.empty?
            mapping_hash["runtime"] = runtime_fields.to_h do |f|
              [f.name_in_index, f.mapping.merge({"script" => {"source" => f.runtime_field_script}})]
            end
          end

          mapping_hash
        end
      end
    end
  end
end
