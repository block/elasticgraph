# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "graphql"

module ElasticGraph
  class GraphQL
    module Resolvers
      # Provides a way to avoid N+1 request problems by batching up multiple
      # datastore queries into one `msearch` request. In general, it is recommended
      # that you use this from any resolver that needs to query the datastore, to
      # maximize our ability to combine multiple datastore requests. Importantly,
      # this should never be instantiated directly; instead use the `execute` method from below.
      #
      # Note: `NestedRelationshipsSource` implements further optimizations on top of this, and should
      # be used rather than this class when applicable.
      class QuerySource < ::GraphQL::Dataloader::Source
        def initialize(datastore_router, query_tracker)
          @datastore_router = datastore_router
          @query_tracker = query_tracker
        end

        def fetch(queries)
          responses_by_query = @datastore_router.msearch(queries, query_tracker: @query_tracker)
          queries.map { |q| responses_by_query.fetch(q) }
        end

        def self.execute_many(queries, for_context:)
          datastore_router = for_context.fetch(:datastore_search_router)
          query_tracker = for_context.fetch(:elastic_graph_query_tracker)
          dataloader = for_context.dataloader

          responses = dataloader.with(self, datastore_router, query_tracker).load_all(queries)
          queries.zip(responses).to_h
        end

        def self.execute_one(query, for_context:)
          execute_many([query], for_context: for_context).fetch(query)
        end
      end
    end
  end
end
