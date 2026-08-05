# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

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

        # The registered adapters, keyed by the function name used in runtime metadata.
        BY_NAME = {
          avg: SimpleMetric.new(datastore_function_name: "avg", empty_bucket_value: nil),
          cardinality: SimpleMetric.new(datastore_function_name: "cardinality", empty_bucket_value: 0),
          max: SimpleMetric.new(datastore_function_name: "max", empty_bucket_value: nil),
          min: SimpleMetric.new(datastore_function_name: "min", empty_bucket_value: nil),
          sum: SimpleMetric.new(datastore_function_name: "sum", empty_bucket_value: 0)
        }.freeze
      end
    end
  end
end
