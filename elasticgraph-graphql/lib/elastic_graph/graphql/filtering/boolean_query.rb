# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Filtering
      # BooleanQuery is an internal class for composing a datastore query:
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-bool-query.html
      #
      # It is composed of:
      #   1) The occurrence type (:filter, :should, or :must_not)
      #   2) A list of query clauses evaluated by the given occurrence type
      #   3) An optional flag indicating whether the occurrence should be negated
      #
      # Note: since we never do anything with the score, we always prefer `filter` over `must`. If we ever
      # decide to do something with the score (such as sorting by it), then we'll want to introduce `must`.
      class BooleanQuery < ::Data.define(:occurrence, :clauses)
        def self.filter(*clauses)
          unwrapped_clauses = clauses.map do |clause|
            __skip__ = case clause
            in {bool: {minimum_should_match: 1, should: [::Hash => single_should], **nil}, **nil}
              # This case represents an `anyOf` with a single subfilter (`filter: {anyOf: [X]}`).
              # Such an expression is semantically equivalent to `filter: X`, and we can unwrap the
              # should clause in this case since there is only a single one.
              #
              # While it adds a bit of complexity to do this unwrapping, we believe it's worth it because
              # it preserves the datastore's ability to apply caching. As the Elasticsearch documentation[^1]
              # explains, the results of `filter` clauses can be cached, but not `should` clauses.
              #
              # [^1]: https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-bool-query
              single_should
            else
              clause
            end
          end

          new(:filter, unwrapped_clauses)
        end

        def self.should(*clauses)
          new(:should, clauses)
        end

        def merge_into(bool_node)
          bool_node[occurrence].concat(clauses)
        end

        ALWAYS_FALSE_FILTER = filter({match_none: {}})
      end
    end
  end
end
