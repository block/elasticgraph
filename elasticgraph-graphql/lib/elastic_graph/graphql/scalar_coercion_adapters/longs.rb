# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"

module ElasticGraph
  class GraphQL
    module ScalarCoercionAdapters
      class Longs
        def self.to_ruby_int_in_range(value, min, max)
          value = Integer(value, exception: false)
          return nil if value.nil? || value > max || value < min
          value
        end
      end

      class JsonSafeLong
        def self.coerce_input(value, ctx)
          Longs.to_ruby_int_in_range(value, JSON_SAFE_LONG_MIN, JSON_SAFE_LONG_MAX)
        end

        def self.coerce_result(value, ctx)
          Longs.to_ruby_int_in_range(value, JSON_SAFE_LONG_MIN, JSON_SAFE_LONG_MAX)
        end
      end

      class LongString
        def self.coerce_input(value, ctx)
          # Do not allow non-string input, to guard against the value potentially having been rounded off by
          # the client before it got serialized into a JSON request.
          return nil unless value.is_a?(::String)

          Longs.to_ruby_int_in_range(value, LONG_STRING_MIN, LONG_STRING_MAX)
        end

        def self.coerce_result(value, ctx)
          Longs.to_ruby_int_in_range(value, LONG_STRING_MIN, LONG_STRING_MAX)&.to_s
        end
      end
    end
  end
end
