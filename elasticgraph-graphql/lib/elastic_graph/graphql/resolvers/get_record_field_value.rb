# Copyright 2024 - 2026 Block, Inc.
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
      # Responsible for fetching a single field value from a document.
      class GetRecordFieldValue
        def initialize(elasticgraph_graphql:, config:)
        end

        def resolve(field:, object:, args:, context:)
          data =
            case object
            when DatastoreResponse::Document
              object.payload
            else
              object
            end

          value = Support::HashUtil.fetch_value_at_path(data, field.path_in_index) { nil }
          value = [] if value.nil? && field.type.list?

          if field.type.relay_connection?
            RelayConnection::ArrayAdapter.build(value, args, context)
          else
            value
          end
        end
      end
    end
  end
end
