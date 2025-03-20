# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module ScalarCoercionAdapters
      # No-op implementation of coercion interface. Used as the default adapter.
      class NoOp
        def self.coerce_input(value, ctx)
          value
        end

        def self.coerce_result(value, ctx)
          value
        end
      end
    end
  end
end
