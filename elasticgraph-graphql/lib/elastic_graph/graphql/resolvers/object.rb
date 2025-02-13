# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Resolvers
      # Resolver which just delegates to `object` for resolving.
      class Object
        def call(field, object, args, context)
          object.call(field, object, args, context)
        end
      end
    end
  end
end
