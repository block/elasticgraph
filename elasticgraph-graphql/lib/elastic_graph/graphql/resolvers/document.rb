# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/datastore_response/document"
require "elastic_graph/graphql/resolvers/relay_connection/array_adapter"
require "elastic_graph/support/hash_util"

module ElasticGraph
  class GraphQL
    module Resolvers
      # Responsible for fetching a single field value from a datastore document.
      class Document
        def initialize(hash_resolver:)
          @hash_resolver = hash_resolver
        end

        def call(parent_type, graphql_field, object, args, context)
          @hash_resolver.call(parent_type, graphql_field, object.payload, args, context)
        end
      end
    end
  end
end
