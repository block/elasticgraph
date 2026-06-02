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
          case value
          when DecodedCursor
            value.encode
          when ::String
            value
          end
        end

        def self.coerce_result(value, ctx)
          # Pass-through: resolvers already encode cursors to strings
          value
        end
      end
    end
  end
end
