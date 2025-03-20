# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "did_you_mean"
require "elastic_graph/graphql/scalar_coercion_adapters/valid_time_zones"

module ElasticGraph
  class GraphQL
    module ScalarCoercionAdapters
      class TimeZone
        SUGGESTER = ::DidYouMean::SpellChecker.new(dictionary: VALID_TIME_ZONES.to_a)

        def self.coerce_input(value, ctx)
          return value if value.nil? || VALID_TIME_ZONES.include?(value)

          suggestions = SUGGESTER.correct(value).map(&:inspect)
          suggestion_sentence =
            if suggestions.size >= 3
              *initial, final = suggestions
              " Possible alternatives: #{initial.join(", ")}, or #{final}."
            elsif suggestions.size == 1
              " Possible alternative: #{suggestions.first}."
            elsif suggestions.size > 0
              " Possible alternatives: #{suggestions.join(" or ")}."
            end

          raise ::GraphQL::CoercionError,
            "Could not coerce value #{value.inspect} to TimeZone: must be a valid IANA time zone identifier " \
            "(such as `America/Los_Angeles` or `UTC`).#{suggestion_sentence}"
        end

        def self.coerce_result(value, ctx)
          return value if value.nil? || VALID_TIME_ZONES.include?(value)
          nil
        end
      end
    end
  end
end
