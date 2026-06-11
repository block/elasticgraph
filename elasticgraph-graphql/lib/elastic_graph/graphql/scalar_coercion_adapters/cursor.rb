# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module ScalarCoercionAdapters
      # Coercion adapter for the Cursor scalar type.
      # Validates that cursor values are strings. When given a non-string value, returns nil
      # to trigger GraphQL-Ruby's validation error with full field context.
      class Cursor
        def self.coerce_input(value, ctx)
          return value if value.nil? || value.is_a?(::String)
          nil # Returning nil causes GraphQL-Ruby to generate a validation error
        end

        def self.coerce_result(value, ctx)
          value
        end
      end
    end
  end
end
