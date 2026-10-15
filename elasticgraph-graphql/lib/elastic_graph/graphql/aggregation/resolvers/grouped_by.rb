# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/field_path_encoder"
require "elastic_graph/support/hash_util"

module ElasticGraph
  class GraphQL
    module Aggregation
      module Resolvers
        class GroupedBy < ::Data.define(:bucket, :field_path)
          def resolve(field:, object:, args:, context:, lookahead:)
            return with(field_path: field_path_for(field, lookahead)) if field.type.object?

            value = key_value_for(field: field, lookahead: lookahead)

            if field.type.unwrap_fully.name == "Boolean"
              work_around_terms_aggregation_boolean_value(value)
            else
              value
            end
          end

          # Reads a raw grouping key using the selected field's full path and aliases.
          def key_value_for(field:, lookahead:)
            bucket_entry = Support::HashUtil.verbose_fetch(bucket, "key")
            Support::HashUtil.verbose_fetch(bucket_entry, FieldPathEncoder.encode(field_path_for(field, lookahead).map(&:name_in_graphql_query)))
          end

          private

          # Extends the grouping path with the selected field, including any client alias.
          def field_path_for(field, lookahead)
            field_path + [PathSegment.for(field: field, lookahead: lookahead)]
          end

          # Elasticsearch/OpenSearch generally return `true`/`false` for Boolean fields. However, there's one exception to that[^1]:
          #
          # > Aggregations like the terms aggregation use 1 and 0 for the key, and the strings "true" and "false" for the key_as_string.
          #
          # Since we get 0/1 in _only_ this one case, we translate it back to false/true here. While a bit hacky, there isn't a widespread
          # need to handle Booleans like this in other places. It would be nice to apply this logic in the `NonCompositeGroupingAdapter`
          # (since the `composite` aggregation used by the `CompositeGroupingAdapter` does not suffer from this issue!) but we don't have
          # ready access to the field type there to know that 0/1 mean false/true.
          #
          # [^1]: https://www.elastic.co/guide/en/elasticsearch/reference/8.17/boolean.html
          def work_around_terms_aggregation_boolean_value(value)
            return false if value == 0
            return true if value == 1
            value
          end
        end
      end
    end
  end
end
