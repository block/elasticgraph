# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/untyped_encoder"

module ElasticGraph
  class GraphQL
    module ScalarCoercionAdapters
      class Untyped
        def self.coerce_input(value, ctx)
          Support::UntypedEncoder.encode(value).tap do |encoded|
            # Check to see if the encoded form, when parsed as JSON, gives us back the original value. If not,
            # it's not a valid `Untyped` value!
            if Support::UntypedEncoder.decode(encoded) != value
              raise ::GraphQL::CoercionError,
                "Could not coerce value #{value.inspect} to `Untyped`: not representable as JSON."
            end
          end
        end

        def self.coerce_result(value, ctx)
          Support::UntypedEncoder.decode(value) if value.is_a?(::String)
        end
      end
    end
  end
end
