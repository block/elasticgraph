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
require "elastic_graph/graphql/aggregation/key"
require "elastic_graph/graphql/aggregation/nested_sub_aggregation"
require "elastic_graph/graphql/aggregation/non_composite_grouping_adapter"
require "elastic_graph/graphql/aggregation/path_segment"
require "elastic_graph/graphql/aggregation/query"
require "elastic_graph/graphql/aggregation/script_term_grouping"
require "elastic_graph/schema_artifacts/runtime_metadata/computation_detail"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"

module ElasticGraph
  module AggregationsHelpers
    def computation_of(*field_names_in_index, function, computed_field_name: function.to_s, field_names_in_graphql_query: field_names_in_index)
      source_field_path = build_field_path(names_in_index: field_names_in_index, names_in_graphql_query: field_names_in_graphql_query)

      GraphQL::Aggregation::Computation.new(
        source_field_path: source_field_path,
        computed_index_field_name: computed_field_name,
        detail: SchemaArtifacts::RuntimeMetadata::ComputationDetail.new(
          function: function,
          empty_bucket_value: (function == :sum || function == :cardinality) ? 0 : nil
        )
      )
    end

    def date_histogram_grouping_of(
      *field_names_in_index,
      interval,
      time_zone: "UTC",
      offset: nil,
      graphql_subfield: nil,
      field_names_in_graphql_query: field_names_in_index + [graphql_subfield].compact
    )
      field_path = build_field_path(names_in_index: field_names_in_index, names_in_graphql_query: field_names_in_graphql_query)
      GraphQL::Aggregation::DateHistogramGrouping.new(field_path, interval, time_zone, offset)
    end

    def as_time_of_day_grouping_of(
      *field_names_in_index,
      interval,
      offset_ms: 0,
      time_zone: "UTC",
      graphql_subfield: nil,
      field_names_in_graphql_query: field_names_in_index + [graphql_subfield].compact,
      script_id: nil,
      runtime_metadata: nil
    )
      script_id ||= runtime_metadata.static_script_ids_by_scoped_name.fetch("field/as_time_of_day")
      params = {"interval" => interval, "offset_ms" => offset_ms, "time_zone" => time_zone}.compact
      script_term_grouping_of(*field_names_in_index, script_id: script_id, field_names_in_graphql_query: field_names_in_graphql_query, params: params)
    end

    def as_day_of_week_grouping_of(
      *field_names_in_index,
      offset_ms: 0,
      time_zone: "UTC",
      graphql_subfield: nil,
      field_names_in_graphql_query: field_names_in_index + [graphql_subfield].compact,
      script_id: nil,
      runtime_metadata: nil
    )
      script_id ||= runtime_metadata.static_script_ids_by_scoped_name.fetch("field/as_day_of_week")
      params = {"time_zone" => time_zone, "offset_ms" => offset_ms}.compact
      script_term_grouping_of(*field_names_in_index, script_id: script_id, field_names_in_graphql_query: field_names_in_graphql_query, params: params)
    end

    def script_term_grouping_of(
      *field_names_in_index,
      script_id:,
      field_names_in_graphql_query: field_names_in_index,
      params: {}
    )
      field_path = build_field_path(names_in_index: field_names_in_index, names_in_graphql_query: field_names_in_graphql_query)
      GraphQL::Aggregation::ScriptTermGrouping.new(field_path: field_path, script_id: script_id, params: params)
    end

    def field_term_grouping_of(*field_names_in_index, field_names_in_graphql_query: field_names_in_index)
      field_path = build_field_path(names_in_index: field_names_in_index, names_in_graphql_query: field_names_in_graphql_query)
      GraphQL::Aggregation::FieldTermGrouping.new(field_path: field_path)
    end

    def nested_sub_aggregation_of(path_in_index: nil, query: nil, path_in_graphql_query: path_in_index)
      field_path = build_field_path(names_in_index: path_in_index, names_in_graphql_query: path_in_graphql_query)
      GraphQL::Aggregation::NestedSubAggregation.new(nested_path: field_path, query: query)
    end

    def sub_aggregation_query_of(grouping_adapter: GraphQL::Aggregation::NonCompositeGroupingAdapter, **options)
      aggregation_query_of(grouping_adapter: grouping_adapter, **options)
    end

    # Default values for `default_page_size` and `max_page_size` come from `config/settings/test.yaml.template`
    def aggregation_query_of(
      name: "aggregations",
      grouping_adapter: GraphQL::Aggregation::CompositeGroupingAdapter,
      computations: [],
      groupings: [],
      sub_aggregations: [],
      needs_doc_count: false,
      needs_doc_count_error: false,
      filter: nil,
      first: nil,
      after: nil,
      last: nil,
      before: nil,
      default_page_size: 50,
      max_page_size: 500
    )
      schema_element_names = SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: :snake_case, overrides: {})
      sub_aggs_hash = sub_aggregations.to_h { |sa| [sa.nested_path_key, sa] }

      # Verify that we didn't lose any sub-aggregations by having conflicting keys
      expect(sub_aggs_hash.values).to match_array(sub_aggregations)

      GraphQL::Aggregation::Query.new(
        name: name,
        grouping_adapter: grouping_adapter,
        computations: computations.to_set,
        groupings: groupings.to_set,
        sub_aggregations: sub_aggs_hash,
        needs_doc_count: needs_doc_count,
        needs_doc_count_error: needs_doc_count_error,
        filter: filter,
        paginator: GraphQL::DatastoreQuery::Paginator.new(
          first: first,
          after: after,
          last: last,
          before: before,
          default_page_size: default_page_size,
          max_page_size: max_page_size,
          schema_element_names: schema_element_names
        )
      )
    end

    def aggregated_value_key_of(*field_path, function_name, aggregation_name: "aggregations")
      GraphQL::Aggregation::Key::AggregatedValue.new(
        aggregation_name: aggregation_name,
        field_path: field_path,
        function_name: function_name
      )
    end

    # The `QueryOptimizer` assumes that `Aggregation::Query` will always produce aggregation keys
    # using `Aggregation::Query#name` such that `Aggregation::Key.extract_aggregation_name_from` is able
    # to extract the original name from response keys. If that is violated, it will not work properly and
    # subtle bugs can result.
    #
    # This helper method is used from our unit and integration tests for `DatastoreQuery` to verify that
    # that requirement is satisfied.
    def verify_aggregations_satisfy_optimizer_requirements(aggregations, for_query:)
      return if aggregations.nil?

      actual_agg_names = aggregations.keys.map do |key|
        GraphQL::Aggregation::Key.extract_aggregation_name_from(key)
      end

      expected_agg_names = for_query.aggregations.values.flat_map do |agg|
        # For groupings/computations, we expect a single key if we have any groupings;
        # if not, we expect one per computation since each computation will go directly
        # at the root.
        count = agg.groupings.empty? ? agg.computations.size : 1

        # In addition, each sub-aggregation gets its own key.
        count += agg.sub_aggregations.size

        [agg.name] * count
      end

      expect(actual_agg_names).to match_array(expected_agg_names)
    end

    private

    def build_field_path(names_in_index:, names_in_graphql_query:)
      names_in_graphql_query.zip(names_in_index).map do |name_in_graphql_query, name_in_index|
        GraphQL::Aggregation::PathSegment.new(
          name_in_graphql_query: name_in_graphql_query,
          name_in_index: name_in_index
        )
      end
    end
  end
end
