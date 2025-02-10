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
      # Responsible for fetching a single field value from a document.
      class GetRecordFieldValue
        def initialize(schema_element_names:)
          @schema_element_names = schema_element_names
        end

        def call(parent_type, graphql_field, object, args, context)
          field = context.fetch(:elastic_graph_schema).field_named(parent_type.graphql_name, graphql_field.name)
          field_name = field.name_in_index.to_s
          data =
            case object
            when DatastoreResponse::Document
              object.payload
            else
              object
            end

          value = Support::HashUtil.fetch_value_at_path(data, field_name) do
            field.type.list? ? [] : nil
          end

          if field.type.relay_connection?
            args = field.args_to_schema_form(args.except(:lookahead))
            RelayConnection::ArrayAdapter.build(value, args, @schema_element_names, context)
          else
            value
          end
        end
      end
    end
  end
end
