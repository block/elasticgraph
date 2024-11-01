# Copyright 2024 Block, Inc.
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
      #   1) The occurrence type (:must, :filter, :should, or :must_not)
      #   2) A list of query clauses evaluated by the given occurrence type
      #   3) An optional flag indicating whether the occurrence should be negated
      class BooleanQuery < ::Data.define(:occurrence, :clauses)
        def self.must(*clauses)
          new(:must, clauses)
        end

        def self.filter(*clauses)
          new(:filter, clauses)
        end

        def self.should(*clauses)
          new(:should, clauses)
        end

        def merge_into(bool_node)
          bool_node[occurrence].concat(clauses)
        end

        MATCH_ALL = {match_all: {}}
        MATCH_ALL_FILTER = filter(MATCH_ALL)
        MATCH_ALL_FILTER_HASH = {bool: {filter: [MATCH_ALL]}}
        MATCH_NONE = {match_none: {}}
        MATCH_NONE_FILTER = filter(MATCH_NONE)
        MATCH_NONE_FILTER_HASH = {bool: {filter: [MATCH_NONE]}}
      end
    end
  end
end
