# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/enum"
require "elastic_graph/schema_artifacts/runtime_metadata/sort_field"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Responsible for generating enum types based on specific indexed types.
      #
      # @private
      class EnumsForIndexedTypes
        def initialize(schema_def_state)
          @schema_def_state = schema_def_state
        end

        # Generates a `SortOrder` enum type for the given indexed type.
        def sort_order_enum_for(indexed_type)
          return nil unless indexed_type.indexed?

          build_enum(indexed_type, :sort_order, :sortable?, "sorted") do |enum_type, field_path|
            value_name_parts = field_path.map(&:name)
            index_field = field_path.map(&:name_in_index).join(".")

            {asc: "ascending", desc: "descending"}.each do |dir, dir_description|
              enum_type.value((value_name_parts + [dir.to_s.upcase]).join("_")) do |v|
                v.update_runtime_metadata sort_field: SchemaArtifacts::RuntimeMetadata::SortField.new(index_field, dir)
                v.documentation "Sorts #{dir_description} by the `#{graphql_field_path_description(field_path)}` field."

                wrapped_enum_value = @schema_def_state.factory.new_sort_order_enum_value(v, field_path)

                field_path.each do |field|
                  field.sort_order_enum_value_customizations.each { |block| block.call(wrapped_enum_value) }
                end
              end
            end
          end
        end

        private

        def build_enum(indexed_type, category, field_predicate, past_tense_verb, &block)
          derived_type_ref = indexed_type.type_ref.as_static_derived_type(category)

          enum = @schema_def_state.factory.new_enum_type(derived_type_ref.name) do |enum_type|
            enum_type.documentation "Enumerates the ways `#{indexed_type.name}`s can be #{past_tense_verb}."
            define_enum_values_for_type(enum_type, indexed_type, field_predicate, &block)
          end.as_input

          enum unless enum.values_by_name.empty?
        end

        def define_enum_values_for_type(enum_type, object_type, field_predicate, parents: [], &block)
          object_type
            .graphql_fields_by_name.values
            .select(&field_predicate)
            .each { |f| define_enum_values_for_field(enum_type, f, field_predicate, parents: parents, &block) }
        end

        def define_enum_values_for_field(enum_type, field, field_predicate, parents:, &block)
          path = parents + [field]

          if (object_type = field.type.fully_unwrapped.as_object_type)
            define_enum_values_for_type(enum_type, object_type, field_predicate, parents: path, &block)
          else
            block.call(enum_type, path)
          end
        end

        def graphql_field_path_description(field_path)
          field_path.map(&:name).join(".")
        end
      end
    end
  end
end
