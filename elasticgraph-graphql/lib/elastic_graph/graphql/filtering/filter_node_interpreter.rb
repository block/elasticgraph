# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql/filtering/boolean_query"
require "elastic_graph/graphql/filtering/range_query"
require "elastic_graph/graphql/schema/enum_value"
require "elastic_graph/support/memoizable_data"
require "elastic_graph/support/time_util"

module ElasticGraph
  class GraphQL
    module Filtering
      # Responsible for interpreting a single `node` in a `filter` expression.
      FilterNodeInterpreter = Support::MemoizableData.define(:runtime_metadata, :schema_names) do
        # @implements FilterNodeInterpreter

        def initialize(runtime_metadata:)
          super(runtime_metadata: runtime_metadata, schema_names: runtime_metadata.schema_element_names)
        end

        def identify_node_type(field_or_op, sub_expression)
          # `:not` must go before `:empty`, because `not: empty_filter` must be inverted from just  `empty_filter`.
          return :not if field_or_op == schema_names.not

          # The `:empty` check can go before all other checks; besides `not`, none of the other operators require special
          # handling when the filter is empty, and we want to detect this as early as possible.
          # Note: `any_of: [empty_filter]` does have special handling, but `any_of: empty_filter` does not.
          return :empty if sub_expression.nil? || sub_expression == {}

          return :list_any_filter if field_or_op == schema_names.any_satisfy
          return :all_of if field_or_op == schema_names.all_of
          return :any_of if field_or_op == schema_names.any_of
          return :operator if filter_operators.key?(field_or_op)
          return :list_count if field_or_op == LIST_COUNTS_FIELD
          return :sub_field if sub_expression.is_a?(::Hash)

          :unknown
        end

        def filter_operators
          @filter_operators ||= build_filter_operators(runtime_metadata)
        end

        private

        def build_filter_operators(runtime_metadata)
          filter_by_time_of_day_script_id = runtime_metadata
            .static_script_ids_by_scoped_name
            .fetch("filter/by_time_of_day")

          {
            schema_names.equal_to_any_of => ->(field_name, value) {
              values = to_datastore_value(value.compact.uniq) # : ::Array[untyped]

              equality_sub_expression =
                if field_name == "id"
                  # Use specialized "ids" query when querying on ID field.
                  # See: https://www.elastic.co/guide/en/elasticsearch/reference/7.15/query-dsl-ids-query.html
                  #
                  # We reject empty strings because we otherwise get an error from the datastore:
                  # "failed to create query: Ids can't be empty"
                  {ids: {values: values - [""]}}
                else
                  {terms: {field_name => values}}
                end

              exists_sub_expression = {exists: {"field" => field_name}}

              if !value.empty? && value.all?(&:nil?)
                BooleanQuery.new(:must_not, [{bool: {filter: [exists_sub_expression]}}])
              elsif value.include?(nil)
                BooleanQuery.filter({bool: {
                  minimum_should_match: 1,
                  should: [
                    {bool: {filter: [equality_sub_expression]}},
                    {bool: {must_not: [{bool: {filter: [exists_sub_expression]}}]}}
                  ]
                }})
              else
                BooleanQuery.filter(equality_sub_expression)
              end
            },
            schema_names.gt => ->(field_name, value) { RangeQuery.new(field_name, :gt, value) },
            schema_names.gte => ->(field_name, value) { RangeQuery.new(field_name, :gte, value) },
            schema_names.lt => ->(field_name, value) { RangeQuery.new(field_name, :lt, value) },
            schema_names.lte => ->(field_name, value) { RangeQuery.new(field_name, :lte, value) },

            schema_names.matches_query => ->(field_name, value) do
              allowed_edits_per_term = value.fetch(schema_names.allowed_edits_per_term).runtime_metadata.datastore_abbreviation

              BooleanQuery.filter({match: {field_name => {
                query: value.fetch(schema_names.query),
                # This is always a string field, even though the value is often an integer
                fuzziness: allowed_edits_per_term.to_s,
                operator: value[schema_names.require_all_terms] ? "AND" : "OR"
              }}})
            end,

            schema_names.matches_phrase => ->(field_name, value) {
              BooleanQuery.filter({match_phrase_prefix: {field_name => {
                query: value.fetch(schema_names.phrase)
              }}})
            },
            schema_names.matches_query_with_prefix => ->(field_name, value) do
              allowed_edits_per_term = value.fetch(schema_names.allowed_edits_per_term).runtime_metadata.datastore_abbreviation

              BooleanQuery.filter({match_bool_prefix: {field_name => {
                query: value.fetch(schema_names.query_with_prefix),
                # This is always a string field, even though the value is often an integer
                fuzziness: allowed_edits_per_term.to_s,
                operator: value[schema_names.require_all_terms] ? "AND" : "OR"
              }}})
            end,

            schema_names.contains => ->(field_name, value) {
              case_insensitive = value[schema_names.ignore_case] || false
              anded_substrings = value[schema_names.all_substrings_of] || []
              ored_substrings = value[schema_names.any_substring_of]

              sub_expressions = anded_substrings.map do |substring|
                substring_clause(field_name, substring, case_insensitive)
              end

              if ored_substrings
                should_sub_expressions = ored_substrings.map do |substring|
                  substring_clause(field_name, substring, case_insensitive)
                end

                sub_expressions << {bool: {minimum_should_match: 1, should: should_sub_expressions}}
              end

              if ored_substrings&.empty?
                BooleanQuery::ALWAYS_FALSE_FILTER
              elsif sub_expressions.size > 0
                BooleanQuery.filter(*sub_expressions)
              end
            },

            schema_names.starts_with => ->(field_name, value) {
              case_insensitive = value[schema_names.ignore_case] || false
              ored_prefixes = value[schema_names.any_prefix_of]

              sub_expressions = (ored_prefixes || []).map do |prefix|
                {prefix: {field_name => {
                  value: prefix,
                  case_insensitive: case_insensitive
                }}}
              end

              if ored_prefixes&.empty?
                BooleanQuery::ALWAYS_FALSE_FILTER
              elsif sub_expressions.size > 0
                BooleanQuery.filter({bool: {minimum_should_match: 1, should: sub_expressions}})
              end
            },

            # This filter operator wraps a geo distance query:
            # https://www.elastic.co/guide/en/elasticsearch/reference/7.10/query-dsl-geo-distance-query.html
            schema_names.near => ->(field_name, value) do
              unit_abbreviation = value.fetch(schema_names.unit).runtime_metadata.datastore_abbreviation

              BooleanQuery.filter({geo_distance: {
                "distance" => "#{value.fetch(schema_names.max_distance)}#{unit_abbreviation}",
                field_name => {
                  "lat" => value.fetch(schema_names.latitude),
                  "lon" => value.fetch(schema_names.longitude)
                }
              }})
            end,

            schema_names.time_of_day => ->(field_name, value) do
              # To filter on time of day, we use the `filter/by_time_of_day` script. We accomplish
              # this with a script because Elasticsearch/OpenSearch do not support this natively, and it's
              # incredibly hard to implement correctly with respect to time zones without using a
              # script. We considered indexing the `time_of_day` as a separate index field
              # that we could directly filter on, but since we need the time of day to be relative
              # to a specific time zone, there's no way to make that work with the reality of
              # daylight savings time. For example, the `America/Los_Angeles` time zone has a -07:00
              # UTC offset for part of the year and a `America/Los_Angeles` -08:00 UTC offset for
              # part of the year. In a script we can use Java time zone APIs to handle this correctly.
              params = {
                field: field_name,
                equal_to_any_of: list_of_nanos_of_day_from(value, schema_names.equal_to_any_of),
                gt: nano_of_day_from(value, schema_names.gt),
                gte: nano_of_day_from(value, schema_names.gte),
                lt: nano_of_day_from(value, schema_names.lt),
                lte: nano_of_day_from(value, schema_names.lte),
                time_zone: value[schema_names.time_zone]
              }.compact

              # If there are no comparison operators, return `nil` instead of a `Clause` so that we avoid
              # invoking the script for no reason. Note that `field` and `time_zone` will always be in
              # `params` so we can't just check for an empty hash here.
              if (params.keys - [:field, :time_zone]).any?
                BooleanQuery.filter({script: {script: {id: filter_by_time_of_day_script_id, params: params}}})
              end
            end
          }.freeze
        end

        def substring_clause(field_name, substring, case_insensitive)
          {wildcard: {field_name => {
            # We squeeze("*") to convert "**" to "*", which is not needed for correctness but is a bit simpler.
            # There's no point in two consecutive "*" wildcards.
            value: "*#{substring}*".squeeze("*"),
            case_insensitive: case_insensitive
          }}}
        end

        def to_datastore_value(value)
          case value
          when ::Array
            value.map { |v| to_datastore_value(v) }
          when Schema::EnumValue
            value.name
          else
            value
          end
        end

        def nano_of_day_from(value, field)
          local_time = value[field]
          Support::TimeUtil.nano_of_day_from_local_time(local_time) if local_time
        end

        def list_of_nanos_of_day_from(value, field)
          value[field]&.map { |t| Support::TimeUtil.nano_of_day_from_local_time(t) }
        end
      end
    end
  end
end
