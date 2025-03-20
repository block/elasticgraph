# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  # Adapts an ElasticGraph GraphQL endpoint to run as a [Rack](https://github.com/rack/rack) application.
  # This allows an ElasticGraph GraphQL endpoint to run inside any [Rack-compatible web
  # framework](https://github.com/rack/rack#supported-web-frameworks), including [Ruby on Rails](https://rubyonrails.org/),
  # or as a stand-alone application. Two configurations are supported:
  #
  # * Use {Rack::GraphQLEndpoint} to serve a GraphQL endpoint.
  # * Use {Rack::GraphiQL} to serve a GraphQL endpoint and the [GraphiQL IDE](https://github.com/graphql/graphiql).
  module Rack
  end
end
