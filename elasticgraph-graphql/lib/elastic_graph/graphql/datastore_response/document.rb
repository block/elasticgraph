# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/decoded_cursor"
require "elastic_graph/support/memoizable_data"
require "elastic_graph/support/hash_util"
require "forwardable"

module ElasticGraph
  class GraphQL
    module DatastoreResponse
      # @private
      # Sentinel value to distinguish "no default given" from an explicit `nil` default in {Document#fetch_value_at}.
      UNSET = ::Object.new.freeze

      # Represents a document fetched from the datastore. Exposes both the raw metadata
      # provided by the datastore and the doc payload itself. In addition, you can treat
      # it just like a document hash using `#[]` or `#fetch`.
      Document = Support::MemoizableData.define(:raw_data, :payload, :decoded_cursor_factory) do
        # @implements Document
        extend Forwardable

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

        def [](key)
          return payload[key] if payload.key?(key)
          docvalue_field(key)&.first
        end

        def fetch(key, default = UNSET)
          return payload[key] if payload.key?(key)
          if (field_values = docvalue_field(key))
            return field_values.first
          end
          return yield(key) if block_given?
          return default unless default.equal?(UNSET)
          raise KeyError, "key not found: #{key.inspect}"
        end

        def fetch_value_at(path, default_value: UNSET)
          Support::HashUtil.fetch_value_at_path(payload, path) do
            if (field_values = docvalue_field(path.join(".")))
              next field_values.first
            end
            next yield(path) if block_given?
            next default_value unless default_value.equal?(UNSET)
            raise KeyError, "path not found: #{path.join(".")}"
          end
        end

        def value_at(path)
          Support::HashUtil.fetch_value_at_path(payload, path) do
            docvalue_field(path.join("."))&.first
          end
        end

        def sort
          raw_data["sort"]
        end

        def version
          payload["version"]
        end

        def highlights
          raw_data["highlight"] || {}
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

        private

        # Returns the doc_values field array for the given key, or nil if not present.
        # Datastore doc_values are always returned as arrays (e.g. `{"name" => ["Bob"]}`).
        def docvalue_field(key)
          raw_data.dig("fields", key)
        end
      end
    end
  end
end
