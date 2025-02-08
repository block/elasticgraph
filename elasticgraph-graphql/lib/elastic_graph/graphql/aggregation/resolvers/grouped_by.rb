# Copyright 2024 Block, Inc.
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
          def can_resolve?(field:, object:)
            true
          end

          def call(parent_type, graphql_field, object, args, context)
            field = context.fetch(:elastic_graph_schema).field_named(parent_type.graphql_name, graphql_field.name)
            new_field_path = field_path + [PathSegment.for(field: field, lookahead: args.fetch(:lookahead))]
            return with(field_path: new_field_path) if field.type.object?

            bucket_entry = Support::HashUtil.verbose_fetch(bucket, "key")
            result = Support::HashUtil.verbose_fetch(bucket_entry, FieldPathEncoder.encode(new_field_path.map(&:name_in_graphql_query)))

            # Give the field a chance to coerce the result before returning it. Initially, this is only used to deal with
            # enum value overrides (e.g. so that if `DayOfWeek.MONDAY` has been overridden to `DayOfWeek.MON`, we can coerce
            # a `MONDAY` value being returned by a painless script to `MON`), but this is designed to be general purpose
            # and we may use it for other coercions in the future.
            field.coerce_result(result)
          end
        end
      end
    end
  end
end
