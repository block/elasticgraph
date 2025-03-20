# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module ClientResolvers
      class ViaHTTPHeader < ::Struct.new(:header_name)
        def initialize(config)
          super(header_name: config.fetch("header_name"))
        end

        def resolve(http_request)
          if (status_code = http_request.normalized_headers["X-CLIENT-RESOLVER-RESPOND-WITH"])
            HTTPResponse.error(status_code.to_i, "Rejected by client resolver")
          else
            Client.new(
              source_description: header_name,
              name: http_request.normalized_headers[header_name]
            )
          end
        end
      end

      class Invalid
      end
    end
  end
end
