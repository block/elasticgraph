# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module QueryRegistry
    # Constants for query registration status values logged in `ElasticGraphQueryExecutorQueryDuration`.
    module RegistrationStatus
      # Query exactly matched a registered query (used from cache).
      MATCHED_REGISTERED_QUERY = "matched_registered_query"

      # Query has same operation name as a registered query but query body differs.
      DIFFERING_REGISTERED_QUERY = "differing_registered_query"

      # Client is registered but has no query with this operation name.
      UNREGISTERED_QUERY = "unregistered_query"

      # Client is not registered in the query registry.
      UNREGISTERED_CLIENT = "unregistered_client"
    end
  end
end
