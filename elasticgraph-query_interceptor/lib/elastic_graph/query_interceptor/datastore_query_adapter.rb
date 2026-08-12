# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module QueryInterceptor
    class DatastoreQueryAdapter
      # @dynamic interceptors
      attr_reader :interceptors

      def initialize(interceptors)
        @interceptors = interceptors
      end

      def call(query:, args:, lookahead:, field:, context:)
        # This extension is only usable in HTTP-serving deployments (per the `_Interceptor#intercept`
        # interface, which requires `http_request:`), so `http_request` is always present here.
        http_request = context.http_request # : GraphQL::HTTPRequest

        interceptors.reduce(query) do |accum, interceptor|
          interceptor.intercept(accum, field: field, args: args, http_request: http_request, context: context)
        end
      end
    end
  end
end
