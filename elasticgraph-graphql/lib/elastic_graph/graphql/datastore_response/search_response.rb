# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/graphql/decoded_cursor"
require "elastic_graph/graphql/datastore_response/document"
require "elastic_graph/support/hash_util"
require "forwardable"

module ElasticGraph
  class GraphQL
    module DatastoreResponse
      # Represents a search response from the datastore. Exposes both the raw metadata
      # provided by the datastore and the collection of documents. Can be treated as a
      # collection of documents when you don't care about the metadata.
      class SearchResponse < ::Data.define(:raw_data, :metadata, :documents, :total_document_count, :aggregations_unavailable_reason, :decoded_cursor_factory)
        include Enumerable
        extend Forwardable

        private :raw_data

        def_delegators :documents, :each, :to_a, :size, :empty?

        EXCLUDED_METADATA_KEYS = %w[hits aggregations].freeze

        def self.build(raw_data, decoded_cursor_factory: DecodedCursor::Factory::Null, aggregations_unavailable_reason: nil)
          documents = raw_data.fetch("hits").fetch("hits").map do |doc|
            Document.build(doc, decoded_cursor_factory: decoded_cursor_factory)
          end

          metadata = raw_data.except(*EXCLUDED_METADATA_KEYS)
          metadata["hits"] = raw_data.fetch("hits").except("hits")

          # `hits.total` is exposed as an object like:
          #
          # {
          #   "value" => 200,
          #   "relation" => "eq", # or "gte"
          # }
          #
          # This allows it to provide a lower bound on the number of hits, rather than having
          # to give an exact count. We may want to handle the `gte` case differently at some
          # point but for now we just use the value as-is.
          #
          # In the case where `track_total_hits` flag is set to `false`, `hits.total` field will be completely absent.
          # This means the client intentionally chose not to query the total doc count, and `total_document_count` will be nil.
          # In this case, we will throw an exception if the client later tries to access `total_document_count`.
          total_document_count = metadata.dig("hits", "total", "value")

          new(
            raw_data:,
            metadata:,
            documents:,
            total_document_count:,
            aggregations_unavailable_reason:,
            decoded_cursor_factory:
          )
        end

        def self.synthesize_from_ids(index, ids, decoded_cursor_factory: DecodedCursor::Factory::Null)
          hits = ids.map do |id|
            {
              "_index" => index,
              "_type" => "_doc",
              "_id" => id,
              "_score" => nil,
              "_source" => {"id" => id},
              "sort" => [id]
            }
          end

          raw_data = {
            "took" => 0,
            "timed_out" => false,
            "_shards" => {
              "total" => 0,
              "successful" => 0,
              "skipped" => 0,
              "failed" => 0
            },
            "hits" => {
              "total" => {
                "value" => ids.size,
                "relation" => "eq"
              },
              "max_score" => nil,
              "hits" => hits
            }
          }

          build(raw_data, decoded_cursor_factory: decoded_cursor_factory)
        end

        # Benign empty response that can be used in place of datastore response errors as needed.
        RAW_EMPTY = {"hits" => {"hits" => [], "total" => {"value" => 0}}}.freeze
        EMPTY = build(RAW_EMPTY)

        # Returns a response filtered to results that have matching `values` at the given `field_path`, limiting
        # the results to the first `size` results.
        #
        # This is designed for use in situations where we have N different datastore queries which are identical
        # except for differing filter values. For efficiency, we combine those queries into a single query that
        # filters on the set union of values. We can then use this method to "split" the single response into what
        # the separate responses would have been if we hadn't combined into a single query.
        def filter_results(field_path, values, size)
          filter =
            if field_path == "id"
              # `id` filtering is a very common case, and we want to avoid having to request
              # `id` within `_source`, given it's available as `_id`.
              ->(hit) { values.include?(hit.fetch("_id")) }
            else
              ->(hit) { values.intersect?(Support::HashUtil.fetch_leaf_values_at_path(hit.fetch("_source"), field_path).to_set) }
            end

          hits = raw_data.fetch("hits").fetch("hits").select(&filter).first(size)
          updated_raw_data = Support::HashUtil.deep_merge(raw_data, {"hits" => {"hits" => hits, "total" => nil}})

          SearchResponse.build(
            updated_raw_data,
            decoded_cursor_factory: decoded_cursor_factory,
            aggregations_unavailable_reason: "aggregations cannot be provided accurately on a search response filtered in memory"
          )
        end

        def docs_description
          (documents.size < 3) ? documents.inspect : "[#{documents.first}, ..., #{documents.last}]"
        end

        def total_document_count(default: nil)
          super() || default || raise(Errors::CountUnavailableError, "#{__method__} is unavailable; set `query.total_document_count_needed = true` to make it available")
        end

        def aggregations
          if (reason = aggregations_unavailable_reason)
            raise Errors::AggregationsUnavailableError, "Aggregations are unavailable on this search response: #{reason}."
          end

          raw_data["aggregations"] || {}
        end

        def to_s
          "#<#{self.class.name} size=#{documents.size} #{docs_description}>"
        end
        alias_method :inspect, :to_s
      end
    end
  end
end
