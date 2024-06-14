# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/composite_grouping_adapter"
require "elastic_graph/graphql/aggregation/computation"
require "elastic_graph/graphql/aggregation/date_histogram_grouping"
require "elastic_graph/graphql/aggregation/field_term_grouping"
require "elastic_graph/graphql/aggregation/nested_sub_aggregation"
require "elastic_graph/graphql/aggregation/path_segment"
require "elastic_graph/graphql/aggregation/query"
require "elastic_graph/graphql/aggregation/script_term_grouping"
require "elastic_graph/graphql/schema/arguments"
require "elastic_graph/support/hash_util"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  class GraphQL
    module Aggregation
      # Responsible for taking in the incoming GraphQL request context, arguments, and the GraphQL
      # schema and directives and populating the `aggregations` portion of `query`.
      class QueryAdapter < Support::MemoizableData.define(:schema, :config, :filter_args_translator, :runtime_metadata, :sub_aggregation_grouping_adapter)
        # Partially applied `QueryAdapter` -- essentially the `QueryAdapter` without the schema,
        # so that it can be instantiated before the `Schema` instance exists, instead providing it from
        # `context` at query time.
        class WithoutSchema
          def initialize(config:, filter_args_translator:, runtime_metadata:, sub_aggregation_grouping_adapter:)
            @build_adapter = ->(schema) do
              QueryAdapter.new(
                schema: schema,
                config: config,
                filter_args_translator: filter_args_translator,
                runtime_metadata: runtime_metadata,
                sub_aggregation_grouping_adapter: sub_aggregation_grouping_adapter
              )
            end
          end

          def call(query:, lookahead:, args:, field:, context:)
            return query unless field.type.unwrap_fully.indexed_aggregation?

            @build_adapter.call(context.fetch(:elastic_graph_schema)).call(
              query: query,
              lookahead: lookahead,
              args: args,
              field: field,
              context: context
            )
          end
        end

        # @dynamic element_names
        attr_reader :element_names

        def call(query:, lookahead:, args:, field:, context:)
          aggregations_node = extract_aggregation_node(lookahead, field, context.query)
          return query unless aggregations_node

          aggregation_query = build_aggregation_query_for(
            aggregations_node,
            field: field,
            grouping_adapter: CompositeGroupingAdapter,
            # Filters on root aggregations applied to the search query body itself instead of
            # using a filter aggregation, like sub-aggregations do, so we don't want a filter
            # aggregation generated here.
            unfiltered: true
          )

          query.merge_with(aggregations: {aggregation_query.name => aggregation_query})
        end

        private

        def after_initialize
          @element_names = schema.element_names
        end

        def extract_aggregation_node(lookahead, field, graphql_query)
          return nil unless (ast_nodes = lookahead.ast_nodes)

          if ast_nodes.size > 1
            names = ast_nodes.map { |n| "`#{name_of(n)}`" }
            raise_conflicting_grouping_requirement_selections("`#{lookahead.name}` selection with the same name", names)
          end

          ::GraphQL::Execution::Lookahead.new(
            query: graphql_query,
            ast_nodes: ast_nodes,
            field: lookahead.field,
            owner_type: field.parent_type.graphql_type
          )
        end

        def build_aggregation_query_for(aggregations_node, field:, grouping_adapter:, nested_path: [], unfiltered: false)
          aggregation_name = name_of(_ = aggregations_node.ast_nodes.first)

          # Get the AST node for the `nodes` subfield (e.g. from `fooAggregations { nodes { ... } }`)
          nodes_node = selection_above_grouping_fields(aggregations_node, element_names.nodes, aggregation_name)

          # Also get the AST node for `edges.node` (e.g. from `fooAggregations { edges { node { ... } } }`)
          edges_node_node = [element_names.edges, element_names.node].reduce(aggregations_node) do |node, sub_selection|
            selection_above_grouping_fields(node, sub_selection, aggregation_name)
          end

          # ...and then determine which one is being used for nodes.
          node_node =
            if nodes_node.selected? && edges_node_node.selected?
              raise_conflicting_grouping_requirement_selections("node selection", ["`#{element_names.nodes}`", "`#{element_names.edges}.#{element_names.node}`"])
            elsif !nodes_node.selected?
              edges_node_node
            else
              nodes_node
            end

          count_detail_node = node_node.selection(element_names.count_detail)
          needs_doc_count_error =
            # We need to know what the error is to determine if the approximate count is in fact the exact count.
            count_detail_node.selects?(element_names.exact_value) ||
            # We need to know what the error is to determine the upper bound on the count.
            count_detail_node.selects?(element_names.upper_bound)

          unless unfiltered
            filter = filter_args_translator.translate_filter_args(field: field, args: field.args_to_schema_form(aggregations_node.arguments))
          end

          Query.new(
            name: aggregation_name,
            groupings: build_groupings_from(node_node, aggregation_name, from_field_path: nested_path),
            computations: build_computations_from(node_node, from_field_path: nested_path),
            sub_aggregations: build_sub_aggregations_from(node_node, parent_nested_path: nested_path),
            needs_doc_count: count_detail_node.selected? || node_node.selects?(element_names.count),
            needs_doc_count_error: needs_doc_count_error,
            paginator: build_paginator_for(aggregations_node),
            filter: filter,
            grouping_adapter: grouping_adapter
          )
        end

        # Helper method for dealing with lookahead selections above the grouping fields. If the caller selects
        # such a field multiple times (e.g. with aliases) it leads to conflicting grouping requirements, so we
        # do not allow it.
        def selection_above_grouping_fields(node, sub_selection_name, aggregation_name)
          node.selection(sub_selection_name).tap do |nested_node|
            ast_nodes = nested_node.ast_nodes || []
            if ast_nodes.size > 1
              names = ast_nodes.map { |n| "`#{name_of(n)}`" }
              raise_conflicting_grouping_requirement_selections("`#{sub_selection_name}` selection under `#{aggregation_name}`", names)
            end
          end
        end

        def build_clauses_from(parent_node, &block)
          get_children_nodes(parent_node).flat_map do |child_node|
            transform_node_to_clauses(child_node, &block)
          end.to_set
        end

        # Takes a `GraphQL::Execution::Lookahead` node and returns an array of children
        # lookahead nodes, excluding nodes for introspection fields.
        def get_children_nodes(node)
          node.selections.reject do |child|
            child.field.introspection?
          end
        end

        # Takes a `GraphQL::Execution::Lookahead` node that conforms to our aggregate field
        # conventions (`some_field: {Type}Metric`) and returns a Hash compatible with the `aggregations`
        # argument to `DatastoreQuery.new`.
        def transform_node_to_clauses(node, parent_path: [], &clause_builder)
          field = field_from_node(node)
          field_path = parent_path + [PathSegment.for(field: field, lookahead: node)]

          clause_builder.call(node, field, field_path) || get_children_nodes(node).flat_map do |embedded_field|
            transform_node_to_clauses(embedded_field, parent_path: field_path, &clause_builder)
          end
        end

        def build_computations_from(node_node, from_field_path: [])
          aggregated_values_node = node_node.selection(element_names.aggregated_values)

          build_clauses_from(aggregated_values_node) do |node, field, field_path|
            if field.aggregated?
              field_path = from_field_path + field_path

              get_children_nodes(node).map do |fn_node|
                computed_field = field_from_node(fn_node)
                computation_detail = field_from_node(fn_node).computation_detail # : SchemaArtifacts::RuntimeMetadata::ComputationDetail

                Aggregation::Computation.new(
                  source_field_path: field_path,
                  computed_index_field_name: computed_field.name_in_index,
                  detail: computation_detail
                )
              end
            end
          end
        end

        def build_groupings_from(node_node, aggregation_name, from_field_path: [])
          grouped_by_node = selection_above_grouping_fields(node_node, element_names.grouped_by, aggregation_name)

          build_clauses_from(grouped_by_node) do |node, field, field_path|
            field_path = from_field_path + field_path

            # New date/time grouping API (DateGroupedBy, DateTimeGroupedBy)
            if field.type.elasticgraph_category == :date_grouped_by_object
              date_time_groupings_from(field_path: field_path, node: node)
            elsif !field.type.object?
              # Non-date/time grouping
              [FieldTermGrouping.new(field_path: field_path)]
            end
          end
        end

        # Given a `GraphQL::Execution::Lookahead` node, returns the corresponding `Schema::Field`
        def field_from_node(node)
          schema.field_named(node.owner_type.graphql_name, node.field.name)
        end

        # Returns an array of `...Grouping`, one for each child node (`as_date_time`, `as_date`, etc).
        def date_time_groupings_from(field_path:, node:)
          get_children_nodes(node).map do |child_node|
            schema_args = Schema::Arguments.to_schema_form(child_node.arguments, child_node.field)
            # Because `DateGroupedBy` doesn't have a `timeZone` argument, and we want to reuse the same
            # script for both `Date` and `DateTime`, we fall back to "UTC" here.
            time_zone = schema_args[element_names.time_zone] || "UTC"
            child_field_path = field_path + [PathSegment.for(lookahead: child_node)]

            if child_node.field.name == element_names.as_day_of_week
              ScriptTermGrouping.new(
                field_path: child_field_path,
                script_id: runtime_metadata.static_script_ids_by_scoped_name.fetch("field/as_day_of_week"),
                params: {
                  "offset_ms" => datetime_offset_as_ms_from(child_node, schema_args),
                  "time_zone" => time_zone
                }
              )
            elsif child_node.field.name == element_names.as_time_of_day
              ScriptTermGrouping.new(
                field_path: child_field_path,
                script_id: runtime_metadata.static_script_ids_by_scoped_name.fetch("field/as_time_of_day"),
                params: {
                  "interval" => interval_from(child_node, schema_args),
                  "offset_ms" => datetime_offset_as_ms_from(child_node, schema_args),
                  "time_zone" => time_zone
                }
              )
            else
              DateHistogramGrouping.new(
                field_path: child_field_path,
                interval: interval_from(child_node, schema_args),
                offset: datetime_offset_from(child_node, schema_args),
                time_zone: time_zone
              )
            end
          end
        end

        # Figure out the Date histogram grouping interval for the given node based on the `grouped_by` argument.
        def interval_from(node, schema_args)
          enum_type_name = node.field.arguments.fetch(element_names.truncation_unit).type.unwrap.graphql_name
          enum_value_name = schema_args.fetch(element_names.truncation_unit)
          enum_value = schema.type_named(enum_type_name).enum_value_named(enum_value_name)

          _ = enum_value.runtime_metadata.datastore_value
        end

        def datetime_offset_from(node, schema_args)
          if (unit_name = schema_args.dig(element_names.offset, element_names.unit))
            enum_value = enum_value_from_offset(node, unit_name)
            amount = schema_args.fetch(element_names.offset).fetch(element_names.amount)
            "#{amount}#{enum_value.runtime_metadata.datastore_abbreviation}"
          end
        end

        # Convert from amount and unit to milliseconds, using runtime metadata `datastore_value`
        def datetime_offset_as_ms_from(node, schema_args)
          unit_name = schema_args.dig(element_names.offset, element_names.unit)
          return 0 unless unit_name

          amount = schema_args.fetch(element_names.offset).fetch(element_names.amount)
          enum_value = enum_value_from_offset(node, unit_name)

          amount * enum_value.runtime_metadata.datastore_value
        end

        def enum_value_from_offset(node, unit_name)
          offset_input_type = node.field.arguments.fetch(element_names.offset).type.unwrap # : ::GraphQL::Schema::InputObject
          enum_type_name = offset_input_type.arguments.fetch(element_names.unit).type.unwrap.graphql_name
          schema.type_named(enum_type_name).enum_value_named(unit_name)
        end

        def name_of(ast_node)
          ast_node.alias || ast_node.name
        end

        def build_sub_aggregations_from(node_node, parent_nested_path: [])
          key_sub_agg_pairs =
            build_clauses_from(node_node.selection(element_names.sub_aggregations)) do |node, field, field_path|
              if field.type.elasticgraph_category == :nested_sub_aggregation_connection
                nested_path = parent_nested_path + field_path
                nested_sub_agg = NestedSubAggregation.new(
                  nested_path: nested_path,
                  query: build_aggregation_query_for(
                    node,
                    field: field,
                    grouping_adapter: sub_aggregation_grouping_adapter,
                    nested_path: nested_path
                  )
                )

                [[nested_sub_agg.nested_path_key, nested_sub_agg]] # : ::Array[[::String, NestedSubAggregation]]
              end
            end

          Support::HashUtil.strict_to_h(key_sub_agg_pairs)
        end

        def build_paginator_for(node)
          args = field_from_node(node).args_to_schema_form(node.arguments)

          DatastoreQuery::Paginator.new(
            first: args[element_names.first],
            after: args[element_names.after],
            last: args[element_names.last],
            before: args[element_names.before],
            default_page_size: config.default_page_size,
            max_page_size: config.max_page_size,
            schema_element_names: schema.element_names
          )
        end

        def raise_conflicting_grouping_requirement_selections(more_than_one_description, paths)
          raise ::GraphQL::ExecutionError, "Cannot have more than one #{more_than_one_description} " \
            "(#{paths.join(", ")}), because that could lead to conflicting grouping requirements."
        end
      end
    end
  end
end
