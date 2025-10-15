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
      # @!parse class FieldReference < ::Data; end
      FieldReference = ::Data.define(
        :name,
        :name_in_index,
        :type,
        :mapping_options,
        :json_schema_options,
        :accuracy_confidence,
        :source,
        :runtime_field_script,
        :doc_comment
      )

      # A lazy reference to a {Field}. It contains all attributes needed to build a {Field}, but the referenced `type` may not be
      # resolvable yet (which is why this exists).
      #
      # @api private
      class FieldReference < ::Data
        # @return [Field, nil] the {Field} this reference resolves to (if it can be resolved)
        def resolve
          return nil unless (resolved_type = type.fully_unwrapped.resolved)

          Indexing::Field.new(
            name: name,
            name_in_index: name_in_index,
            type: type,
            json_schema_layers: type.json_schema_layers,
            indexing_field_type: resolved_type.to_indexing_field_type,
            accuracy_confidence: accuracy_confidence,
            json_schema_customizations: json_schema_options,
            mapping_customizations: mapping_options,
            source: source,
            runtime_field_script: runtime_field_script,
            doc_comment: doc_comment
          )
        end

        # @dynamic initialize, with, name, name_in_index, type, mapping_options, json_schema_options, accuracy_confidence, source, runtime_field_script, doc_comment
      end
    end
  end
end
