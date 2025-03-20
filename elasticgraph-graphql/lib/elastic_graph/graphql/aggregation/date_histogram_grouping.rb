# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql/aggregation/field_path_encoder"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  class GraphQL
    module Aggregation
      # Represents a grouping of a timestamp field into a date histogram.
      # For the relevant Elasticsearch docs, see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/7.12/search-aggregations-bucket-datehistogram-aggregation.html
      # https://www.elastic.co/guide/en/elasticsearch/reference/7.12/search-aggregations-bucket-composite-aggregation.html#_date_histogram
      class DateHistogramGrouping < Support::MemoizableData.define(:field_path, :interval, :time_zone, :offset)
        def key
          @key ||= FieldPathEncoder.encode(field_path.map(&:name_in_graphql_query))
        end

        def encoded_index_field_path
          @encoded_index_field_path ||= FieldPathEncoder.join(field_path.filter_map(&:name_in_index))
        end

        def composite_clause(grouping_options: {})
          interval_options = INTERVAL_OPTIONS_BY_NAME.fetch(interval) do
            raise ArgumentError, "#{interval.inspect} is an unsupported interval. Valid values: #{INTERVAL_OPTIONS_BY_NAME.keys.inspect}."
          end

          inner_hash = interval_options.merge(grouping_options).merge({
            "field" => encoded_index_field_path,
            "format" => DATASTORE_DATE_TIME_FORMAT,
            "offset" => offset,
            "time_zone" => time_zone
          }.compact)

          {"date_histogram" => inner_hash}
        end

        def non_composite_clause_for(query)
          # `min_doc_count: 1` is important so we don't have excess buckets when there is a large gap
          # between document dates. For example, if you group on a field at the year truncation unit, and
          # a one-off rogue document has an incorrect timestamp for hundreds of years ago, you'll wind
          # up with a bucket for each intervening year. `min_doc_count: 1` excludes those empty buckets.
          composite_clause(grouping_options: {"min_doc_count" => 1})
        end

        def inner_meta
          INNER_META
        end

        INNER_META = {
          # On a date histogram aggregation, the `key` is formatted as a number (milliseconds since epoch). We
          # need it formatted as a string, which `key_as_string` provides.
          "key_path" => ["key_as_string"],
          # Date histogram aggregations do not have any doc count error. Our resolver is generic and expects
          # there to always be a `doc_count_error_upper_bound`. So we want to tell it to merge an error of `0`
          # into each bucket.
          "merge_into_bucket" => {"doc_count_error_upper_bound" => 0}
        }

        INTERVAL_OPTIONS_BY_NAME = {
          # These intervals have only fixed intervals...
          "millisecond" => {"fixed_interval" => "1ms"},
          "second" => {"fixed_interval" => "1s"},
          # ...but the rest have calendar intervals, which we prefer.
          "minute" => {"calendar_interval" => "minute"},
          "hour" => {"calendar_interval" => "hour"},
          "day" => {"calendar_interval" => "day"},
          "week" => {"calendar_interval" => "week"},
          "month" => {"calendar_interval" => "month"},
          "quarter" => {"calendar_interval" => "quarter"},
          "year" => {"calendar_interval" => "year"}
        }
        private_constant :INTERVAL_OPTIONS_BY_NAME
      end
    end
  end
end
