# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/support/hash_util"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      module FieldType
        # Responsible for the mapping of a {SchemaElements::ObjectType}.
        #
        # @!attribute [r] type_name
        #   @return [String] name of the object type
        # @!attribute [r] subfields
        #   @return [Array<Field>] the subfields of this object type
        # @!attribute [r] mapping_options
        #   @return [Hash<String, ::Object>] options to be included in the mapping
        # @!attribute [r] doc_comment
        #   @return [String, nil] documentation for the type
        #
        # @api private
        class Object < Support::MemoizableData.define(:schema_def_state, :type_name, :subfields, :mapping_options, :doc_comment)
          # @return [Hash<String, ::Object>] the datastore mapping for this object type.
          def to_mapping
            @to_mapping ||= begin
              base_mapping = Field.normalized_mapping_hash_for(subfields)
              # When a custom mapping type is used, we need to omit `properties`, because custom mapping
              # types generally don't use `properties` (and if you need to use `properties` with a custom
              # type, you're responsible for defining the properties).
              base_mapping = base_mapping.except("properties") if (mapping_options[:type] || "object") != "object"
              base_mapping.merge(Support::HashUtil.stringify_keys(mapping_options))
            end
          end

          # @private
          def after_initialize
            subfields.freeze
          end
        end
      end
    end
  end
end
