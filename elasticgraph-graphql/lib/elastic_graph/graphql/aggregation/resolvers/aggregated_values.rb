# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/key"
require "elastic_graph/graphql/aggregation/path_segment"
require "elastic_graph/support/hash_util"

module ElasticGraph
  class GraphQL
    module Aggregation
      module Resolvers
        class AggregatedValues < ::Data.define(:aggregation_name, :bucket, :field_path)
          def resolve(field:, object:, args:, context:, lookahead:)
            return with(field_path: field_path + [PathSegment.for(field: field, lookahead: lookahead)]) if field.type.object?

            key = Key::AggregatedValue.new(
              aggregation_name: aggregation_name,
              field_path: field_path.map(&:name_in_graphql_query),
              function_name: field.name_in_index
            )

            result = Support::HashUtil.verbose_fetch(bucket, key.encode)

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
