# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "apollo-federation/tracing"

module ElasticGraph
  module Apollo
    module GraphQL
      # This extension is designed to hook `ElasticGraph::GraphQL::HTTPEndpoint` in order
      # to provide Apollo Federated Tracing:
      #
      # https://www.apollographql.com/docs/federation/metrics/
      #
      # Luckily, the apollo-federation gem supports this--we just need to:
      #
      # 1. Use the `ApolloFederation::Tracing` plugin (implemented via `EngineExtension#graphql_gem_plugins`).
      # 2. Conditionally pass `tracing_enabled: true` into in `context`.
      #
      # This extension handles the latter requirement. For more info, see:
      # https://github.com/Gusto/apollo-federation-ruby#tracing
      #
      # @private
      module HTTPEndpointExtension
        def with_context(request)
          # Steep has an error here for some reason:
          # UnexpectedError: undefined method `selector' for #<Parser::Source::Map::Keyword:0x0000000131979b18>
          __skip__ = super(request) do |context|
            # `ApolloFederation::Tracing.should_add_traces` expects the header to be in SCREAMING_SNAKE_CASE with an HTTP_ prefix:
            # https://github.com/Gusto/apollo-federation-ruby/blob/v3.8.4/lib/apollo-federation/tracing.rb#L5
            normalized_headers = request.headers.transform_keys { |key| "HTTP_#{key.upcase.tr("-", "_")}" }

            if ApolloFederation::Tracing.should_add_traces(normalized_headers)
              context = context.merge(tracing_enabled: true)
            end

            yield context
          end
        end
      end
    end
  end
end
