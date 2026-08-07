# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/key"
require "elastic_graph/graphql/aggregation/path_segment"
require "elastic_graph/support/hash_util"
require "graphql"

module ElasticGraph
  class GraphQL
    module Aggregation
      module Resolvers
        class AggregatedValues < ::Data.define(:schema, :aggregation_name, :bucket, :field_path)
          def resolve(field:, object:, args:, context:, lookahead:)
            return with(field_path: field_path + [PathSegment.for(field: field, lookahead: lookahead)]) if field.type.object?

            function_adapter = field.function_adapter # : FunctionAdapter::adapter

            # `QueryAdapter` detected any invalid args when the query was built, but it can't report an
            # error there without failing resolution of the entire aggregations field rather than just
            # this one leaf--so it omits the datastore clause for an invalid field instead. Here, at
            # resolve time, we're resolving this specific field, so we can report the error at the
            # correct, precise path.
            #
            # `args` is already in schema form here (`GraphQLAdapterBuilder` converts it before calling
            # `resolve`), unlike at query-build time where `QueryAdapter` converts the raw AST arguments
            # itself--so, unlike there, we pass `args` through as-is rather than re-converting it.
            function_adapter.extract_args(args, schema.element_names) do |message|
              error = ::GraphQL::ExecutionError.new(message)

              # Neither `context.add_error` nor `context.execution_errors.add` sets `path` for us--that
              # only happens automatically when an `ExecutionError` is raised and returned as a field's
              # own resolution result, which isn't the case here since we're continuing on to resolve
              # sibling fields normally. So we set `path` ourselves from `context.current_path`, which
              # is already the precise path to this field (e.g. `[..., "aggregatedValues", "amountCents",
              # "p150"]`), so the error in the response is attributed to this specific field.
              error.path = context.current_path
              context.add_error(error)
              return nil
            end

            key = Key::AggregatedValue.new(
              aggregation_name: aggregation_name,
              field_path: field_path.map(&:name_in_graphql_query),
              function_name: PathSegment.for(field: field, lookahead: lookahead).name_in_graphql_query
            )

            result = function_adapter.extract_result(Support::HashUtil.verbose_fetch(bucket, key.encode))

            # Aggregated value results always have a `value` key; in addition, for `date` field, they also have a `value_as_string`.
            # In that case, `value` is a number (e.g. ms since epoch) whereas `value_as_string` is a formatted value. ElasticGraph
            # works with date types as formatted strings, so we need to use `value_as_string` here if it is present.
            result.fetch("value_as_string") { result.fetch("value") }
          end
        end
      end
    end
  end
end
