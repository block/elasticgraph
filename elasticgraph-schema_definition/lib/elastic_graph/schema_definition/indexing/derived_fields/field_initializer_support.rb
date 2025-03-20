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
      # Contains implementation logic for the different kinds of derived fields.
      #
      # @api private
      module DerivedFields
        # Contains helper logic for field initialization applicable to all types of derived fields.
        #
        # @api private
        module FieldInitializerSupport
          # Painless literal for an empty list, from [the docs](https://www.elastic.co/guide/en/elasticsearch/painless/8.15/painless-operators-reference.html#list-initialization-operator).
          EMPTY_PAINLESS_LIST = "[]"

          # Painless literal for an empty map, from [the docs](https://www.elastic.co/guide/en/elasticsearch/painless/8.15/painless-operators-reference.html#map-initialization-operator).
          EMPTY_PAINLESS_MAP = "[:]"

          # @return [Array<String>] a list of painless statements that will initialize a given `destination_field` path to an empty value.
          def self.build_empty_value_initializers(destination_field, leaf_value:)
            snippets = [] # : ::Array[::String]
            path_so_far = [] # : ::Array[::String]

            destination_field.split(".").each do |path_part|
              path_to_this_part = (path_so_far + [path_part]).join(".")
              is_leaf = path_to_this_part == destination_field

              unless is_leaf && leaf_value == :leave_unset
                # The empty value of all parent fields must be an empty painless map, but for a leaf field it can be different.
                empty_value = is_leaf ? leaf_value : EMPTY_PAINLESS_MAP

                snippets << default_source_field_to_empty(path_to_this_part, empty_value.to_s)
                path_so_far << path_part
              end
            end

            snippets
          end

          # @return [String] a painless statement that will default a single field to an empty value.
          def self.default_source_field_to_empty(field_path, empty_value)
            <<~EOS.strip
              if (ctx._source.#{field_path} == null) {
                ctx._source.#{field_path} = #{empty_value};
              }
            EOS
          end
        end
      end
    end
  end
end
