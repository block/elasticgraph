# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module QueryRegistry
    module QueryValidators
      # Query validator implementation used for unregistered or anonymous clients.
      ForUnregisteredClient = ::Data.define(:allow_unregistered_clients, :allow_any_query_for_clients) do
        # @implements ForUnregisteredClient
        def build_and_validate_query_with_registration_status(query_string, client:, variables: {}, operation_name: nil, context: {})
          query = yield

          return [query, [], false] if allow_unregistered_clients

          client_name = client&.name
          return [query, [], false] if client_name && allow_any_query_for_clients.include?(client_name)

          [query, [
            "Client #{client&.description || "(unknown)"} is not a registered client, it is not in " \
            "`allow_any_query_for_clients` and `allow_unregistered_clients` is false."
          ], false]
        end
      end
    end
  end
end
