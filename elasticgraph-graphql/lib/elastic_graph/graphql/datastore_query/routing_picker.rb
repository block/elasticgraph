# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/filtering/filter_value_set_extractor"

module ElasticGraph
  class GraphQL
    class DatastoreQuery
      # Responsible for picking routing values for a specific query based on the filters.
      class RoutingPicker
        def initialize(filter_node_interpreter:, schema_names:)
          @filter_value_set_extractor = Filtering::FilterValueSetExtractor.for_equality(filter_node_interpreter, schema_names)
        end

        # Given a list of `filter_hashes` and a list of `routing_field_paths`, returns a list of
        # routing values that can safely be used to limit what index shards we search
        # without risking missing any matching documents that could exist on other shards.
        #
        # If an eligible list of routing values cannot be determined, returns `nil`.
        #
        # Importantly, we have to be careful to not return routing values unless we are 100% sure
        # that the set of values will route to the full set of shards on which documents matching
        # the filters could live. If a document matching the filters lived on a shard that our
        # search does not route to, it will not be included in the search response.
        #
        # Essentially, this method guarantees that the following pseudo code is always satisfied:
        #
        # ``` ruby
        # if (routing_values = extract_eligible_routing_values(filter_hashes, routing_field_paths))
        #   Datastore.all_documents_matching(filter_hashes).each do |document|
        #     routing_field_paths.each do |field_path|
        #       expect(routing_values).to include(document.value_at(field_path))
        #     end
        #   end
        # end
        # ```
        def extract_eligible_routing_values(filter_hashes, routing_field_paths)
          result = @filter_value_set_extractor.extract_filter_value_set(filter_hashes, routing_field_paths)
          # Elasticsearch/OpenSearch have no routing value syntax to tell it to avoid searching a specific shard
          # (and the fact that we are excluding a routing value doesn't mean that other documents that
          # live on the same shard with different routing values can't match!) so we return `nil` to
          # force the datastore to search all shards.
          return nil if result.nil? || result.exclusive?
          result.values.to_a
        end
      end

      # `Query::RoutingPicker` exists only for use by `Query` and is effectively private.
      private_constant :RoutingPicker

      # Steep can't find implementations of these `DatastoreQuery` methods because they're defined in `datastore_query.rb`, not in this file.
      # @dynamic shard_routing_values, effective_size, merge_with, search_index_expression, narrowed_search_index_definitions, with, to_datastore_msearch_header_and_body
    end
  end
end
