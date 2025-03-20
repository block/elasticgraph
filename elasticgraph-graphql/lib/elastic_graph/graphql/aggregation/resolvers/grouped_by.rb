# Copyright 2024 - 2025 Block, Inc.
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
            new_field_path = field_path + [PathSegment.for(field: field, lookahead: lookahead)]
            return with(field_path: new_field_path) if field.type.object?

            bucket_entry = Support::HashUtil.verbose_fetch(bucket, "key")
            value = Support::HashUtil.verbose_fetch(bucket_entry, FieldPathEncoder.encode(new_field_path.map(&:name_in_graphql_query)))

            if field.type.unwrap_fully.name == "Boolean"
              work_around_terms_aggregation_boolean_value(value)
            else
              value
            end
          end

          private

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
