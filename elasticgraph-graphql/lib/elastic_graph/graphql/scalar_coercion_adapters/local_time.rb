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
      class LocalTime
        def self.coerce_input(value, ctx)
          validated_value(value) || raise(::GraphQL::CoercionError,
            "Could not coerce value #{value.inspect} to LocalTime: must be formatted as an RFC3339 partial time (such as `14:23:12` or `07:05:23.555`")
        end

        def self.coerce_result(value, ctx)
          validated_value(value)
        end

        private_class_method def self.validated_value(value)
          value if value.is_a?(::String) && VALID_LOCAL_TIME_REGEX.match?(value)
        end
      end
    end
  end
end
