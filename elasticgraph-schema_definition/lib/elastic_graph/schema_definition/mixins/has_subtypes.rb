# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_definition/indexing/field_type/union"
require "elastic_graph/schema_definition/schema_elements/list_counts_state"

module ElasticGraph
  module SchemaDefinition
    module Mixins
      # Provides common support for abstract GraphQL types that have subtypes (e.g. union and interface types).
      #
      # @private
      module HasSubtypes
        def to_indexing_field_type
          subtypes_by_name = recursively_resolve_subtypes.to_h do |type|
            [type.name, _ = type.to_indexing_field_type]
          end

          Indexing::FieldType::Union.new(subtypes_by_name)
        end

        def graphql_fields_by_name
          merge_fields_by_name_from_subtypes(&:graphql_fields_by_name)
        end

        def indexing_fields_by_name_in_index
          merge_fields_by_name_from_subtypes(&:indexing_fields_by_name_in_index)
            .merge("__typename" => schema_def_state.factory.new_field(name: "__typename", type: "String", parent_type: _ = self))
        end

        def indexed?
          super || subtypes_indexed?
        end

        def recursively_resolve_subtypes
          resolve_subtypes.flat_map do |type|
            type.is_a?(HasSubtypes) ? (_ = type).recursively_resolve_subtypes : [type]
          end
        end

        def abstract?
          true
        end

        def current_sources
          resolve_subtypes.flat_map(&:current_sources)
        end

        def index_field_runtime_metadata_tuples(
          path_prefix: "",
          parent_source: SELF_RELATIONSHIP_NAME,
          list_counts_state: SchemaElements::ListCountsState::INITIAL
        )
          resolve_subtypes.flat_map do |t|
            t.index_field_runtime_metadata_tuples(
              path_prefix: path_prefix,
              parent_source: parent_source,
              list_counts_state: list_counts_state
            )
          end
        end

        private

        def merge_fields_by_name_from_subtypes
          resolved_subtypes = resolve_subtypes

          resolved_subtypes.reduce(_ = {}) do |fields_by_name, subtype|
            fields_by_name.merge(yield subtype) do |field_name, def1, def2|
              if (def1.name_in_index == def2.name_in_index && def1.resolve_mapping != def2.resolve_mapping) || (def1.type.unwrap_non_null != def2.type.unwrap_non_null)
                def_strings = resolved_subtypes.each_with_object([]) do |st, defs|
                  if (field = st.graphql_fields_by_name[field_name])
                    defs << "on #{st.name}:\n#{field.to_sdl.strip} mapping: #{field.resolve_mapping.inspect}"
                  end
                end

                raise Errors::SchemaError,
                  "Conflicting definitions for field `#{field_name}` on the subtypes of `#{name}`. " \
                  "Their definitions must agree. Defs:\n\n#{def_strings.join("\n\n")}"
              end

              def1
            end
          end
        end

        def subtypes_indexed?
          indexed_by_subtype_name = resolve_subtypes.to_h do |subtype, acc|
            [subtype.name, subtype.indexed?]
          end

          uniq_indexed = indexed_by_subtype_name.values.uniq

          if uniq_indexed.size > 1
            descriptions = indexed_by_subtype_name.map do |name_value|
              name, value = name_value
              "#{name}: indexed? = #{value}"
            end

            raise Errors::SchemaError,
              "The #{self.class.name} #{name} has some indexed subtypes, and some non-indexed subtypes. " \
              "All subtypes must be indexed or all must NOT be indexed. Subtypes:\n" \
              "#{descriptions.join("\n")}"
          end

          !!uniq_indexed.first
        end
      end
    end
  end
end
