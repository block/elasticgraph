# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"

module ElasticGraph
  module Support
    # @private
    module FaradayMiddleware
      # Faraday supports specifying a timeout at both the client level (when building the Faraday connection) or on a
      # per-request basis. We want to specify it on a per-request basis, but unfortunately, the Elasticsearch/OpenSearch
      # clients don't provide any per-request API to specify the timeout (it only supports it when instantiating your
      # client).
      #
      # This middleware helps us work around this deficiency by looking for the TIMEOUT_MS_HEADER. If present, it deletes
      # it from the headers and instead sets it as the request timeout.
      # @private
      SupportTimeouts = ::Data.define(:app) do
        # @implements SupportTimeouts

        # Processes a Faraday request, extracting timeout from headers and applying it to the request.
        # Converts {TIMEOUT_MS_HEADER} from request headers into a Faraday request timeout setting.
        #
        # @param env [Faraday::Env] the Faraday request environment
        # @return [Faraday::Response] the response from the next middleware in the stack
        # @raise [Errors::RequestExceededDeadlineError] if the request times out
        def call(env)
          if (timeout_ms = env.request_headers.delete(TIMEOUT_MS_HEADER))
            env.request.timeout = Integer(timeout_ms) / 1000.0
          end

          app.call(env)
        rescue ::Faraday::TimeoutError
          raise Errors::RequestExceededDeadlineError, "Datastore request exceeded timeout of #{timeout_ms} ms."
        end
      end
    end
  end
end
