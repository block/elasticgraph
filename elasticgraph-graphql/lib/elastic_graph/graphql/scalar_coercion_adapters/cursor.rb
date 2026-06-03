# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/decoded_cursor"

module ElasticGraph
  class GraphQL
    module ScalarCoercionAdapters
      class Cursor
        def self.coerce_input(value, ctx)
          return value if value.nil? || value.is_a?(::String)
          raise ::GraphQL::CoercionError, "Cursor must be a String, got #{value.class}"
        end

        def self.coerce_result(value, ctx)
          value
        end
      end
    end
  end
end
