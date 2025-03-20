# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/resolvable_value"

module ElasticGraph
  class GraphQL
    module Aggregation
      module Resolvers
        # Resolves the detailed `count` sub-fields of a sub-aggregation. It's an object because
        # the count we get from the datastore may not be accurate and we have multiple
        # fields we expose to give the client control over how much detail they want.
        #
        # Note: for now our resolver logic only uses the bucket fields returned to us by the datastore,
        # but I believe we may have some opportunities to provide more accurate responses to these when custom shard
        # routing and/or index rollover are in use. For example, when grouping on the custom shard routing field,
        # we know that no term bucket will have data from more than one shard. The datastore isn't aware of our
        # custom shard routing logic, though, and can't account for that in what it returns, so it may indicate
        # a potential error upper bound where we can deduce there is none.
        class CountDetail < GraphQL::Resolvers::ResolvableValue.new(:bucket)
          # The (potentially approximate) `doc_count` returned by the datastore for a bucket.
          def approximate_value
            @approximate_value ||= bucket.fetch("doc_count")
          end

          # The `doc_count`, if we know it was exact. (Otherwise, returns `nil`).
          def exact_value
            approximate_value if approximate_value == upper_bound
          end

          # The upper bound on how large the doc count could be.
          def upper_bound
            @upper_bound ||= bucket.fetch("doc_count_error_upper_bound") + approximate_value
          end
        end
      end
    end
  end
end
