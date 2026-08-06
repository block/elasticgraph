# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "graphql"

module ElasticGraph
  class GraphQL
    module Aggregation
      # Namespace for the adapters that own the datastore-specific behavior of each aggregated
      # value function (`sum`, `avg`, etc). A function's adapter knows the datastore aggregation
      # it maps to, how to translate its GraphQL arguments into the aggregation clause, how to
      # locate its value in the datastore response, and what response to fabricate for a bucket
      # the datastore omitted.
      #
      # @private
      module FunctionAdapter
        # Adapter for metric aggregations that take no arguments and return a flat
        # `{"value" => ...}` response, which describes all currently supported functions.
        #
        # @private
        class SimpleMetric < ::Data.define(:datastore_function_name, :empty_bucket_value)
          def extract_args(args, element_names)
            {}
          end

          def clause_options(function_args)
            {}
          end

          def extract_result(raw)
            raw
          end

          def empty_bucket_result
            {"value" => empty_bucket_value}
          end
        end

        # Adapter for the `percentiles` aggregation, which takes a `percentile` argument and
        # returns a nested `{"values" => [{"key" => ..., "value" => ...}]}` response rather than
        # the flat `{"value" => ...}` shape `SimpleMetric` handles.
        #
        # @private
        class Percentile < ::Data.define(:datastore_function_name)
          def extract_args(args, element_names)
            percentile = args.fetch(element_names.percentile)

            unless percentile.is_a?(::Numeric) && percentile >= 0 && percentile <= 100
              raise ::GraphQL::ExecutionError, "`#{element_names.percentile}` must be between 0 and 100, but is #{percentile.inspect}."
            end

            {percentile: percentile}
          end

          def clause_options(function_args)
            # `keyed: false` gives us an array response (`"values" => [{"key" => ..., "value" => ...}]`)
            # instead of a string-keyed hash (`"values" => {"50.0" => ...}`), which avoids having to
            # reconstruct the datastore's float-formatted string key to look up our single requested value.
            {"percents" => [function_args.fetch(:percentile)], "keyed" => false}
          end

          def extract_result(raw)
            # We always request exactly one percentile per computation (multiple requested ranks are
            # expressed as multiple aliased GraphQL field selections, each becoming its own computation),
            # so the single entry in `values` is always the one we want.
            raw.fetch("values").first
          end

          def empty_bucket_result
            {"values" => [{"value" => nil}]}
          end
        end

        # The registered adapters, keyed by the function name used in runtime metadata.
        BY_NAME = {
          avg: SimpleMetric.new(datastore_function_name: "avg", empty_bucket_value: nil),
          cardinality: SimpleMetric.new(datastore_function_name: "cardinality", empty_bucket_value: 0),
          max: SimpleMetric.new(datastore_function_name: "max", empty_bucket_value: nil),
          min: SimpleMetric.new(datastore_function_name: "min", empty_bucket_value: nil),
          percentiles: Percentile.new(datastore_function_name: "percentiles"),
          sum: SimpleMetric.new(datastore_function_name: "sum", empty_bucket_value: 0)
        }.freeze
      end
    end
  end
end
