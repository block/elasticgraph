# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Support
    # @private
    module FaradayMiddleware
      # Custom Faraday middleware that forces `msearch` calls to use an HTTP GET instead of an HTTP POST. While not
      # necessary, it preserves a useful property: all "read" calls made by ElasticGraph use an HTTP GET, and HTTP POST
      # requests are "write" calls. This allows the access policy to only grant HTTP GET access from the GraphQL endpoint,
      # which leads to a more secure setup (as the GraphQL endpoint can be blocked from performing any writes).
      #
      # Note: before elasticsearch-ruby 7.9.0, `msearch` used an HTTP GET request, so this simply restores that behavior.
      # This results in an HTTP GET with a request body, but it works just fine and its what the Ruby Elasticsearch client
      # did for years.
      #
      # For more info, see: https://github.com/elastic/elasticsearch-ruby/issues/1005
      MSearchUsingGetInsteadOfPost = ::Data.define(:app) do
        # @implements MSearchUsingGetInsteadOfPost
        def call(env)
          env.method = :get if env.url.path.to_s.end_with?("/_msearch")
          app.call(env)
        end
      end
    end
  end
end
