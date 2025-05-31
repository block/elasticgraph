# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module Mixins
      # Responsible for building object types for filtering and aggregation, from an existing object type.
      #
      # This is specifically designed to support {SchemaElements::TypeWithSubfields} (where we have the fields directly available) and
      # {SchemaElements::UnionType} (where we will need to compute the list of fields by resolving the subtypes and merging their fields).
      #
      # @private
      module SupportsFilteringAndAggregation
        # Indicates if this type supports a given feature (e.g. `filterable?`).
        def supports?(&feature_predicate)
          # If the type uses a custom mapping type we don't know if it can support a feature, so we assume it can't.
          # TODO: clean this up using an interface instead of checking mapping options.
          return false if has_custom_mapping_type?

          graphql_fields_by_name.values.any?(&feature_predicate)
        end

        # Inverse of `supports?`.
        def does_not_support?(&feature_predicate)
          !supports?(&feature_predicate)
        end

        def derived_graphql_types
          return [] if graphql_only?

          indexed_agg_type = to_indexed_aggregation_type
          indexed_aggregation_pagination_types =
            if indexed_agg_type
              schema_def_state.factory.build_relay_pagination_types(indexed_agg_type.name)
            else
              [] # : ::Array[SchemaElements::ObjectType]
            end

          sub_aggregation_types = sub_aggregation_types_for_nested_field_references.flat_map do |type|
            [type] + schema_def_state.factory.build_relay_pagination_types(type.name, support_pagination: false) do |t|
              # Record metadata that is necessary for elasticgraph-graphql to correctly recognize and handle
              # this sub-aggregation correctly.
              t.override_runtime_metadata(elasticgraph_category: :nested_sub_aggregation_connection)
              t.default_graphql_resolver = :object_without_lookahead
            end
          end

          document_pagination_types =
            if indexed?
              schema_def_state.factory.build_relay_pagination_types(name, include_total_edge_count: true, derived_indexed_types: (_ = self).derived_indexed_types)
            elsif schema_def_state.paginated_collection_element_types.include?(name)
              schema_def_state.factory.build_relay_pagination_types(name, include_total_edge_count: true)
            else
              [] # : ::Array[SchemaElements::ObjectType]
            end

          sort_order_enum_type = schema_def_state.enums_for_indexed_types.sort_order_enum_for(self)
          derived_sort_order_enum_types = [sort_order_enum_type].compact + (sort_order_enum_type&.derived_graphql_types || [])

          to_input_filters +
            document_pagination_types +
            indexed_aggregation_pagination_types +
            sub_aggregation_types +
            derived_sort_order_enum_types +
            build_aggregation_sub_aggregations_types + [
              indexed_agg_type,
              to_grouped_by_type,
              to_aggregated_values_type,
              to_highlights_type
            ].compact
        end

        def has_custom_mapping_type?
          mapping_type = mapping_options[:type]
          mapping_type && mapping_type != "object"
        end

        private

        # Converts the type to the corresponding input filter type.
        def to_input_filters
          return [] if does_not_support?(&:filterable?)

          schema_def_state.factory.build_standard_filter_input_types_for_index_object_type(name) do |t|
            graphql_fields_by_name.values.each do |field|
              if field.filterable?
                t.graphql_fields_by_name[field.name] = field.to_filter_field(parent_type: t)
              end
            end
          end
        end

        # Generates the `*SubAggregation` types for all of the `mapping type: "nested"` fields that reference this type.
        # A different `*SubAggregation` type needs to be generated for each nested field reference, and for each parent nesting
        # context of that nested field reference. This is necessary because we will support different available `sub_aggregations`
        # based on the parents of a particular nested field.
        #
        # For example, given a `Player` object type definition and a `Team` type definition like this:
        #
        # schema.object_type "Team" do |t|
        #   t.field "id", "ID!"
        #   t.field "name", "String"
        #   t.field "players", "[Player!]!" do |f|
        #     f.mapping type: "nested"
        #   end
        #   t.index "teams"
        # end
        #
        # ...we will generate a `TeamPlayerSubAggregation` type which will have a `sub_aggregations` field which can have
        # `parent_team` and `seasons` fields (assuming `Player` has a `seasons` nested field...).
        def sub_aggregation_types_for_nested_field_references
          schema_def_state.user_defined_field_references_by_type_name.fetch(name) { [] }.select(&:nested?).flat_map do |nested_field_ref|
            schema_def_state.sub_aggregation_paths_for(nested_field_ref.parent_type).map do |path|
              schema_def_state.factory.new_object_type type_ref.as_sub_aggregation(parent_doc_types: path.parent_doc_types).name do |t|
                t.documentation "Return type representing a bucket of `#{name}` objects for a sub-aggregation within each `#{type_ref.as_parent_aggregation(parent_doc_types: path.parent_doc_types).name}`."
                t.default_graphql_resolver = :object_without_lookahead

                t.field schema_def_state.schema_elements.count_detail, "AggregationCountDetail", graphql_only: true do |f|
                  f.documentation "Details of the count of `#{name}` documents in a sub-aggregation bucket."
                end

                if supports?(&:groupable?)
                  t.field schema_def_state.schema_elements.grouped_by, type_ref.as_grouped_by.name, graphql_only: true do |f|
                    f.documentation "Used to specify the `#{name}` fields to group by. The returned values identify each sub-aggregation bucket."
                  end
                end

                if supports?(&:aggregatable?)
                  t.field schema_def_state.schema_elements.aggregated_values, type_ref.as_aggregated_values.name, graphql_only: true do |f|
                    f.documentation "Provides computed aggregated values over all `#{name}` documents in a sub-aggregation bucket."
                  end
                end

                if graphql_fields_by_name.values.any?(&:sub_aggregatable?)
                  sub_aggs_name = type_ref.as_aggregation_sub_aggregations(parent_doc_types: path.parent_doc_types + [name]).name
                  t.field schema_def_state.schema_elements.sub_aggregations, sub_aggs_name, graphql_only: true do |f|
                    f.documentation "Used to perform sub-aggregations of `#{t.name}` data."
                  end
                end
              end
            end
          end
        end

        # Builds the `*AggregationSubAggregations` types. For example, for an indexed type named `Team` which has nested fields,
        # this would generate a `TeamAggregationSubAggregations` type. This type provides access to the various sub-aggregation
        # fields.
        def build_aggregation_sub_aggregations_types
          # The sub-aggregation types do not generate correctly for abstract types, so for now we omit sub-aggregations for abstract types.
          return [] if abstract?

          sub_aggregatable_fields = graphql_fields_by_name.values.select(&:sub_aggregatable?)
          return [] if sub_aggregatable_fields.empty?

          schema_def_state.sub_aggregation_paths_for(self).map do |path|
            agg_sub_aggs_type_ref = type_ref.as_aggregation_sub_aggregations(
              parent_doc_types: path.parent_doc_types,
              field_path: path.field_path
            )

            schema_def_state.factory.new_object_type agg_sub_aggs_type_ref.name do |t|
              under_field_description = "under `#{path.field_path_string}` " unless path.field_path.empty?
              t.documentation "Provides access to the `#{schema_def_state.schema_elements.sub_aggregations}` #{under_field_description}within each `#{type_ref.as_parent_aggregation(parent_doc_types: path.parent_doc_types).name}`."
              t.default_graphql_resolver = :object_with_lookahead

              sub_aggregatable_fields.each do |field|
                if field.nested?
                  unwrapped_type = field.type_for_derived_types.fully_unwrapped
                  field_type_name = unwrapped_type
                    .as_sub_aggregation(parent_doc_types: path.parent_doc_types)
                    .as_connection
                    .name

                  field.define_sub_aggregations_field(parent_type: t, type: field_type_name) do |f|
                    f.argument schema_def_state.schema_elements.filter, unwrapped_type.as_filter_input.name do |a|
                      a.documentation "Used to filter the `#{unwrapped_type.name}` documents included in this sub-aggregation based on the provided criteria."
                    end

                    f.argument schema_def_state.schema_elements.first, "Int" do |a|
                      a.documentation "Determines how many sub-aggregation buckets should be returned."
                    end
                  end
                else
                  field_type_name = type_ref.as_aggregation_sub_aggregations(
                    parent_doc_types: path.parent_doc_types,
                    field_path: path.field_path + [field]
                  ).name

                  field.define_sub_aggregations_field(parent_type: t, type: field_type_name)
                end
              end
            end
          end
        end

        def to_indexed_aggregation_type
          return nil unless indexed?

          schema_def_state.factory.new_object_type type_ref.as_aggregation.name do |t|
            t.documentation "Return type representing a bucket of `#{name}` documents for an aggregations query."

            if supports?(&:groupable?)
              t.field schema_def_state.schema_elements.grouped_by, type_ref.as_grouped_by.name, graphql_only: true do |f|
                f.documentation "Used to specify the `#{name}` fields to group by. The returned values identify each aggregation bucket."
              end
            end

            t.field schema_def_state.schema_elements.count, "JsonSafeLong!", graphql_only: true do |f|
              f.documentation "The count of `#{name}` documents in an aggregation bucket."
            end

            if supports?(&:aggregatable?)
              t.field schema_def_state.schema_elements.aggregated_values, type_ref.as_aggregated_values.name, graphql_only: true do |f|
                f.documentation "Provides computed aggregated values over all `#{name}` documents in an aggregation bucket."
              end
            end

            # The sub-aggregation types do not generate correctly for abstract types, so for now we omit sub-aggregations for abstract types.
            if !abstract? && supports?(&:sub_aggregatable?)
              t.field schema_def_state.schema_elements.sub_aggregations, type_ref.as_aggregation_sub_aggregations.name, graphql_only: true do |f|
                f.documentation "Used to perform sub-aggregations of `#{t.name}` data."
              end
            end

            # Record metadata that is necessary for elasticgraph-graphql to correctly recognize and handle
            # this indexed aggregation type correctly.
            t.default_graphql_resolver = :object_without_lookahead
            t.override_runtime_metadata(source_type: name, elasticgraph_category: :indexed_aggregation)
          end
        end

        def to_grouped_by_type
          # If the type uses a custom mapping type we don't know how it can be aggregated, so we assume it needs no aggregation type.
          # TODO: clean this up using an interface instead of checking mapping options.
          return nil if has_custom_mapping_type?

          new_non_empty_object_type type_ref.as_grouped_by.name do |t|
            t.documentation "Type used to specify the `#{name}` fields to group by for aggregations."
            t.default_graphql_resolver = :object_with_lookahead

            graphql_fields_by_name.values.each do |field|
              field.define_grouped_by_field(t)
            end
          end
        end

        def to_aggregated_values_type
          # If the type uses a custom mapping type we don't know how it can be aggregated, so we assume it needs no aggregation type.
          # TODO: clean this up using an interface instead of checking mapping options.
          return nil if has_custom_mapping_type?

          new_non_empty_object_type type_ref.as_aggregated_values.name do |t|
            t.documentation "Type used to perform aggregation computations on `#{name}` fields."
            t.default_graphql_resolver = :object_with_lookahead

            graphql_fields_by_name.values.each do |field|
              field.define_aggregated_values_field(t)
            end
          end
        end

        def to_highlights_type
          # If the type uses a custom mapping type we don't know how it can be highlighted, so we assume it needs no highlights type.
          return nil if does_not_support?(&:highlightable?)

          new_non_empty_object_type type_ref.as_highlights.name do |t|
            t.documentation "Type used to request desired `#{name}` search highlight fields."
            t.default_graphql_resolver = :get_record_field_value

            graphql_fields_by_name.values.each do |field|
              field.define_highlights_field(t)
            end
          end
        end

        def new_non_empty_object_type(name, &block)
          type = schema_def_state.factory.new_object_type(name, &block)
          type unless type.graphql_fields_by_name.empty?
        end
      end
    end
  end
end
