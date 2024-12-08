# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/filtering/filter_value_set_extractor"
require "elastic_graph/support/time_set"

module ElasticGraph
  class GraphQL
    class DatastoreQuery
      # Responsible for building a search index expression for a specific query based on the filters.
      class IndexExpressionBuilder
        def initialize(schema_names:)
          @filter_value_set_extractor = Filtering::FilterValueSetExtractor.new(schema_names, Support::TimeSet::ALL, Support::TimeSet::EMPTY) do |operator, filter_value|
            case operator
            when :gt, :gte, :lt, :lte
              if date_string?(filter_value)
                # Here we translate into a range of time objects. When translating dates to times,
                # we need to use an appropriate time suffix:
                #
                # - `> 2024-04-01` == `> 2024-04-01T23:59:59.999Z`
                # - `≥ 2024-04-01` == `≥ 2024-04-01T00:00:00Z`
                # - `< 2024-04-01` == `< 2024-04-01T00:00:00Z`
                # - `≤ 2024-04-01` == `≤ 2024-04-01T23:59:59.999Z`
                time_suffix = (operator == :gt || operator == :lte) ? "T23:59:59.999Z" : "T00:00:00Z"
                Support::TimeSet.of_range(operator => ::Time.iso8601(filter_value + time_suffix))
              else
                Support::TimeSet.of_range(operator => ::Time.iso8601(filter_value))
              end
            when :equal_to_any_of
              # This calls `.compact` to remove `nil` timestamp values.
              ranges = filter_value.compact.map do |iso8601_string|
                if date_string?(iso8601_string)
                  # When we have a date string, build a range for the entire day.
                  start_of_day = ::Time.iso8601("#{iso8601_string}T00:00:00Z")
                  end_of_day = ::Time.iso8601("#{iso8601_string}T23:59:59.999Z")
                  ::Range.new(start_of_day, end_of_day)
                else
                  value = ::Time.iso8601(iso8601_string)
                  ::Range.new(value, value)
                end
              end

              Support::TimeSet.of_range_objects(ranges)
            end
          end
        end

        # Returns an index_definition expression string to use for searches. This string can specify
        # multiple indices, use wildcards, etc. For info about what is supported, see:
        # https://www.elastic.co/guide/en/elasticsearch/reference/current/multi-index.html
        def determine_search_index_expression(filter_hashes, search_index_definitions, require_indices:)
          # Here we sort the index expressions. It won't change the behavior in the datastore, but
          # makes the return value here deterministic which makes it easier to assert on in tests.
          search_index_definitions.sort_by(&:name).reduce(IndexExpression::EMPTY) do |index_expression, index_def|
            index_expression + index_expression_for(filter_hashes, index_def, require_indices: require_indices)
          end
        end

        private

        def index_expression_for(filter_hashes, maybe_rollover_index_def, require_indices:)
          unless maybe_rollover_index_def.rollover_index_template?
            return IndexExpression.only(maybe_rollover_index_def.index_expression_for_search)
          end

          # @type var index_def: DatastoreCore::IndexDefinition::RolloverIndexTemplate
          index_def = _ = maybe_rollover_index_def

          time_set = @filter_value_set_extractor.extract_filter_value_set(filter_hashes, [index_def.timestamp_field_path])

          return IndexExpression.only(index_def.index_expression_for_search) if time_set.nil?

          if time_set.empty?
            return require_indices ?
              # Indices are required. Given the time set is empty, it's impossible for any documents to match our search.
              # Therefore, which index we use here doesn't matter. We just pick the first one, alphabetically.
              IndexExpression.only(index_def.known_related_query_rollover_indices.map(&:index_expression_for_search).min) :
              # No indices are required, so we can return an empty index expression.
              IndexExpression::EMPTY
          end

          indices_to_exclude = index_def.known_related_query_rollover_indices.reject do |index|
            time_set.intersect?(index.time_set)
          end

          if require_indices && (index_def.known_related_query_rollover_indices - indices_to_exclude).empty?
            # Indices are required, but all known indices have been excluded. We satisfy the requirement for an index by excluding one
            # less index. This is preferable to the alternative ways to satisfy the requirement.
            #
            # - We could return an `IndexExpression` with no exclusions, but that would search across all indices, which is less efficient.
            # - We could pick the first index to search (as we do for the `time_set.empty?` case), but that could cause matching documents
            #   to be be missed, because it's possible that matching documents exist in just-created index that is not in
            #   `known_related_query_rollover_indices`. Therefore, it's important that we still search the rollover wildcard expression,
            #   and we want to exclude all but one of the known indices.
            indices_to_exclude = indices_to_exclude.drop(1)
          end

          IndexExpression.new(
            names_to_include: ::Set.new([index_def.index_expression_for_search]),
            names_to_exclude: ::Set.new(indices_to_exclude.map(&:index_expression_for_search))
          )
        end

        def date_string?(string)
          /\A\d{4}-\d{2}-\d{2}\z/.match?(string)
        end
      end

      class IndexExpression < ::Data.define(:names_to_include, :names_to_exclude)
        EMPTY = new(names_to_include: ::Set.new, names_to_exclude: ::Set.new)

        def self.only(name)
          IndexExpression.new(names_to_include: ::Set.new([name].compact), names_to_exclude: ::Set.new)
        end

        def to_s
          # Note: exclusions must come after inclusions. I can't find anything in the Elasticsearch or OpenSearch docs
          # that mention this, but when exclusions come first I found that we got errors.
          parts = names_to_include.sort + names_to_exclude.sort.map { |name| "-#{name}" }
          parts.join(",")
        end

        def +(other)
          with(
            names_to_include: names_to_include.union(other.names_to_include),
            names_to_exclude: names_to_exclude.union(other.names_to_exclude)
          )
        end
      end

      # `Query::IndexExpressionBuilder` exists only for use by `Query` and is effectively private.
      private_constant :IndexExpressionBuilder

      # Steep is complaining that it can't find some `Query` but they are not in this file...
      # @dynamic aggregations, shard_routing_values, search_index_definitions, merge_with, search_index_expression
      # @dynamic with, to_datastore_msearch_header_and_body, document_paginator
    end
  end
end
