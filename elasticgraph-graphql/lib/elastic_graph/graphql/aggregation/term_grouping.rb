# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/field_path_encoder"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  class GraphQL
    module Aggregation
      # Represents a grouping on a term.
      # For the relevant Elasticsearch docs, see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/7.12/search-aggregations-bucket-terms-aggregation.html
      # https://www.elastic.co/guide/en/elasticsearch/reference/7.12/search-aggregations-bucket-composite-aggregation.html#_terms
      module TermGrouping
        def key
          @key ||= FieldPathEncoder.encode(field_path.map(&:name_in_graphql_query))
        end

        def encoded_index_field_path
          @encoded_index_field_path ||= FieldPathEncoder.join(field_path.filter_map(&:name_in_index))
        end

        def composite_clause(grouping_options: {})
          {"terms" => terms_subclause.merge(grouping_options)}
        end

        def non_composite_clause_for(query)
          clause_value = work_around_elasticsearch_bug(terms_subclause)
          {
            "terms" => clause_value.merge({
              "size" => query.paginator.desired_page_size,
              "show_term_doc_count_error" => query.needs_doc_count_error
            })
          }
        end

        INNER_META = {"key_path" => ["key"], "merge_into_bucket" => {}}

        def inner_meta
          INNER_META
        end

        private

        # Here we force the `collect_mode` to `depth_first`. Without doing that, we've observed that some of our acceptance
        # specs fail on CI when running against Elasticsearch 8.11 with an error like:
        #
        # ```
        # {
        #   "root_cause": [
        #     {
        #       "type": "runtime_exception",
        #       "reason": "score for different docid, nesting an aggregation under a children aggregation and terms aggregation with collect mode breadth_first isn't possible"
        #     }
        #   ],
        #   "type": "search_phase_execution_exception",
        #   "reason": "all shards failed",
        #   "phase": "query",
        #   "grouped": true,
        #   "failed_shards": [
        #     {
        #       "shard": 0,
        #       "index": "teams_camel",
        #       "node": "pDXJzLTsRJCRjKe83DqipA",
        #       "reason": {
        #         "type": "runtime_exception",
        #         "reason": "score for different docid, nesting an aggregation under a children aggregation and terms aggregation with collect mode breadth_first isn't possible"
        #       }
        #     }
        #   ],
        #   "caused_by": {
        #     "type": "runtime_exception",
        #     "reason": "score for different docid, nesting an aggregation under a children aggregation and terms aggregation with collect mode breadth_first isn't possible",
        #     "caused_by": {
        #       "type": "runtime_exception",
        #       "reason": "score for different docid, nesting an aggregation under a children aggregation and terms aggregation with collect mode breadth_first isn't possible"
        #     }
        #   }
        # }
        # ```
        #
        # This specific exception message was introduced in https://github.com/elastic/elasticsearch/pull/89993, but that was done to provide
        # a better error than a NullPointerException (which is what used to happen). This error also appears to be non-deterministic; I wasn't
        # able to reproduce the CI failure locally until I forced `"collect_mode" => "breadth_first"`, at which point I did see the same error
        # locally. The Elasticsearch docs[^1] mention that a heuristic (partially based on if a field's cardinality is known!) is used to pick
        # whether `breadth_first` or `depth_first` is used when `collect_mode`is not specified:
        #
        # > The `breadth_first` is the default mode for fields with a cardinality bigger than the requested size or when the cardinality is unknown
        # > (numeric fields or scripts for instance).
        #
        # In addition, the docs[^2] make it clear that `depth_first` is usually what you want:
        #
        # > The strategy we outlined previously—building the tree fully and then pruning—is called depth-first and it is the default.
        # > Depth-first works well for the majority of aggregations, but can fall apart in situations like our actors and costars example.
        # >
        # > ...
        # >
        # > Breadth-first should be used only when you expect more buckets to be generated than documents landing in the buckets.
        #
        # So, for now we are forcing the collect mode to `depth_first`, as it avoids an issue with Elasticsearch and is a generally
        # sane default. It may fall over in the case breadth-first is intended for, but we can cross that bridge when it comes.
        #
        # Long term, we're hoping to switch sub-aggregations to use a `composite` aggregation instead of `terms`, rendering this moot.
        #
        # [^1]: https://www.elastic.co/guide/en/elasticsearch/reference/8.11/search-aggregations-bucket-terms-aggregation.html#search-aggregations-bucket-terms-aggregation-collect
        # [^2]: https://www.elastic.co/guide/en/elasticsearch/guide/current/_preventing_combinatorial_explosions.html#_depth_first_versus_breadth_first
        def work_around_elasticsearch_bug(terms_clause)
          terms_clause.merge({"collect_mode" => "depth_first"})
        end
      end
    end
  end
end
