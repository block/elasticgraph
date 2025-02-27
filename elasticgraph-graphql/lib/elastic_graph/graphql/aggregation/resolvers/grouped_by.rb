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
          def resolve(field:, object:, args:, context:, lookahead:)
            new_field_path = field_path + [PathSegment.for(field: field, lookahead: lookahead)]
            return with(field_path: new_field_path) if field.type.object?

            bucket_entry = Support::HashUtil.verbose_fetch(bucket, "key")
            Support::HashUtil.verbose_fetch(bucket_entry, FieldPathEncoder.encode(new_field_path.map(&:name_in_graphql_query)))
          end
        end
      end
    end
  end
end
