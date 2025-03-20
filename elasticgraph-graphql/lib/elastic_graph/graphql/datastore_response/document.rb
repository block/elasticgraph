# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/decoded_cursor"
require "elastic_graph/support/memoizable_data"
require "forwardable"

module ElasticGraph
  class GraphQL
    module DatastoreResponse
      # Represents a document fetched from the datastore. Exposes both the raw metadata
      # provided by the datastore and the doc payload itself. In addition, you can treat
      # it just like a document hash using `#[]` or `#fetch`.
      Document = Support::MemoizableData.define(:raw_data, :payload, :decoded_cursor_factory) do
        # @implements Document
        extend Forwardable
        def_delegators :payload, :[], :fetch

        def self.build(raw_data, decoded_cursor_factory: DecodedCursor::Factory::Null)
          source = raw_data.fetch("_source") do
            {} # : ::Hash[::String, untyped]
          end

          new(
            raw_data: raw_data,
            # Since we no longer fetch _source for id only queries, merge id into _source to take care of that case
            payload: source.merge("id" => raw_data["_id"]),
            decoded_cursor_factory: decoded_cursor_factory
          )
        end

        def self.with_payload(payload)
          build({"_source" => payload})
        end

        def index_name
          raw_data["_index"]
        end

        def index_definition_name
          index_name.split(ROLLOVER_INDEX_INFIX_MARKER).first # : ::String
        end

        def id
          raw_data["_id"]
        end

        def sort
          raw_data["sort"]
        end

        def version
          payload["version"]
        end

        def cursor
          @cursor ||= decoded_cursor_factory.build(raw_data.fetch("sort"))
        end

        def datastore_path
          # Path based on this API:
          # https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-get.html
          "/#{index_name}/_doc/#{id}".squeeze("/")
        end

        def to_s
          "#<#{self.class.name} #{datastore_path}>"
        end
        alias_method :inspect, :to_s
      end
    end
  end
end
