# Copyright 2024 - 2025 Block, Inc.
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
          all_values_set = RoutingValueSet::ALL
          empty_set = RoutingValueSet::EMPTY

          @filter_value_set_extractor = Filtering::FilterValueSetExtractor.new(
            filter_node_interpreter,
            schema_names,
            all_values_set,
            empty_set
          ) do |operator, filter_value|
            if operator == :equal_to_any_of
              # This calls `.compact` to remove `nil` filter_value values
              RoutingValueSet.of(filter_value.compact)
            end
          end
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
          @filter_value_set_extractor.extract_filter_value_set(filter_hashes, routing_field_paths)&.to_return_value
        end
      end

      class RoutingValueSet < Data.define(:type, :routing_values)
        def self.of(routing_values)
          new(:inclusive, routing_values.to_set)
        end

        def self.of_all_except(routing_values)
          new(:exclusive, routing_values.to_set)
        end

        ALL = of_all_except([])
        EMPTY = of([])

        def intersection(other)
          if inclusive? && other.inclusive?
            # Since both sets are inclusive, we can just delegate to `Set#intersection` here.
            RoutingValueSet.of(routing_values.intersection(other.routing_values))
          elsif exclusive? && other.exclusive?
            # Since both sets are exclusive, we need to return an exclusive set of the union of the
            # excluded values. For example, when dealing with positive integers:
            #
            #   s1 = RoutingValueSet.of_all_except([1, 2, 3]) # > 3
            #   s2 = RoutingValueSet.of_all_except([3, 4, 5]) # 1, 2, > 5
            #
            #   s3 = s1.intersection(s2)
            #
            # Here s3 would be all values > 5 (the same as `RoutingValueSet.of_all_except([1, 2, 3, 4, 5])`)
            RoutingValueSet.of_all_except(routing_values.union(other.routing_values))
          else
            # Since one set is inclusive and one set is exclusive, we need to return an inclusive set of
            # `included_values - excluded_values`. For example, when dealing with positive integers:
            #
            #   s1 = RoutingValueSet.of([1, 2, 3]) # 1, 2, 3
            #   s2 = RoutingValueSet.of_all_except([3, 4, 5]) # 1, 2, > 5
            #
            #   s3 = s1.intersection(s2)
            #
            # Here s3 would be just `1, 2`.
            included_values, excluded_values = get_included_and_excluded_values(other)
            RoutingValueSet.of(included_values - excluded_values)
          end
        end

        def union(other)
          if inclusive? && other.inclusive?
            # Since both sets are inclusive, we can just delegate to `Set#union` here.
            RoutingValueSet.of(routing_values.union(other.routing_values))
          elsif exclusive? && other.exclusive?
            # Since both sets are exclusive, we need to return an exclusive set of the intersection of the
            # excluded values. For example, when dealing with positive integers:
            #
            #   s1 = RoutingValueSet.of_all_except([1, 2, 3]) # > 3
            #   s2 = RoutingValueSet.of_all_except([3, 4, 5]) # 1, 2, > 5
            #
            #   s3 = s1.union(s2)
            #
            # Here s3 would be all 1, 2, > 3 (the same as `RoutingValueSet.of_all_except([3])`)
            RoutingValueSet.of_all_except(routing_values.intersection(other.routing_values))
          else
            # Since one set is inclusive and one set is exclusive, we need to return an exclusive set of
            # `excluded_values - included_values`. For example, when dealing with positive integers:
            #
            #   s1 = RoutingValueSet.of([1, 2, 3]) # 1, 2, 3
            #   s2 = RoutingValueSet.of_all_except([3, 4, 5]) # 1, 2, > 5
            #
            #   s3 = s1.union(s2)
            #
            # Here s3 would be 1, 2, 3, > 5 (the same as `RoutingValueSet.of_all_except([4, 5])`)
            included_values, excluded_values = get_included_and_excluded_values(other)
            RoutingValueSet.of_all_except(excluded_values - included_values)
          end
        end

        def negate
          with(type: INVERTED_TYPES.fetch(type))
        end

        INVERTED_TYPES = {inclusive: :exclusive, exclusive: :inclusive}

        def to_return_value
          # Elasticsearch/OpenSearch have no routing value syntax to tell it to avoid searching a specific shard
          # (and the fact that we are excluding a routing value doesn't mean that other documents that
          # live on the same shard with different routing values can't match!) so we return `nil` to
          # force the datastore to search all shards.
          return nil if exclusive?

          routing_values.to_a
        end

        protected

        def inclusive?
          type == :inclusive
        end

        def exclusive?
          type == :exclusive
        end

        private

        def get_included_and_excluded_values(other)
          inclusive? ? [routing_values, other.routing_values] : [other.routing_values, routing_values]
        end
      end

      # `Query::RoutingPicker` exists only for use by `Query` and is effectively private.
      private_constant :RoutingPicker
      # `RoutingValueSet` exists only for use here and is effectively private.
      private_constant :RoutingValueSet

      # Steep is complaining that it can't find some `Query` but they are not in this file...
      # @dynamic aggregations, shard_routing_values, search_index_definitions, merge_with, search_index_expression
      # @dynamic with, to_datastore_msearch_header_and_body, document_paginator
    end
  end
end
