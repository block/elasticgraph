# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/field_path_encoder"
require "elastic_graph/graphql/aggregation/key"
require "elastic_graph/graphql/aggregation/path_segment"

module ElasticGraph
  class GraphQL
    module Aggregation
      # Represents some sort of aggregation computation (min, max, avg, sum, etc) on a field.
      # For the relevant Elasticsearch docs, see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/7.12/search-aggregations-metrics-avg-aggregation.html
      # https://www.elastic.co/guide/en/elasticsearch/reference/7.12/search-aggregations-metrics-max-aggregation.html
      # https://www.elastic.co/guide/en/elasticsearch/reference/7.12/search-aggregations-metrics-min-aggregation.html
      # https://www.elastic.co/guide/en/elasticsearch/reference/7.12/search-aggregations-metrics-sum-aggregation.html
      Computation = ::Data.define(
        :source_field_path,
        # The path segment for the computation function itself (e.g. `exactMin`), potentially aliased.
        :leaf,
        # The adapter that owns this function's datastore-specific behavior.
        :function_adapter,
        # The canonically-keyed GraphQL arguments passed to the function, as produced by
        # `function_adapter.extract_args` at query building time.
        :function_args
      ) do
        # @implements Computation

        def key(aggregation_name:)
          Key::AggregatedValue.new(
            aggregation_name: aggregation_name,
            field_path: source_field_path.map(&:name_in_graphql_query),
            function_name: leaf.name_in_graphql_query
          ).encode
        end

        def clause
          encoded_path = FieldPathEncoder.join(source_field_path.filter_map(&:name_in_index))
          clause_body = {"field" => encoded_path}.merge(function_adapter.clause_options(function_args))
          {function_adapter.datastore_function_name => clause_body}
        end
      end
    end
  end
end
