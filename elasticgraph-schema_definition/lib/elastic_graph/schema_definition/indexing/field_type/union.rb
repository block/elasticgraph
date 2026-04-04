# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/indexing/field_type/object"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      module FieldType
        # Responsible for the JSON schema and mapping of a {SchemaElements::UnionType}.
        #
        # @note In JSON schema, we model this with a `oneOf`, and a `__typename` field on each subtype.
        # @note Within the mapping, we have a single object type that has a set union of the properties
        #   of the subtypes (and also a `__typename` keyword field).
        #
        # @!attribute [r] subtypes_by_name
        #   @return [Hash<String, Object>] the subtypes of the union, keyed by name.
        #
        # @api private
        class Union < ::Data.define(:subtypes_by_name)
          # @return [Hash<String, ::Object>] the datastore mapping for this union type.
          def to_mapping
            mapping_subfields = subtypes_by_name.values.map(&:subfields).reduce([], :union)

            Support::HashUtil.deep_merge(
              Field.normalized_mapping_hash_for(mapping_subfields),
              {"properties" => {"__typename" => {"type" => "keyword"}}}
            )
          end
        end
      end
    end
  end
end
