# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Filtering
      # Responsible for extracting a set of values from query filters, based on a using a custom
      # set type that is able to efficiently model the "all values" case.
      class FilterValueSetExtractor
        def initialize(schema_names, all_values_set, empty_set, &build_set_for_filter)
          @schema_names = schema_names
          @all_values_set = all_values_set
          @empty_set = empty_set
          @build_set_for_filter = build_set_for_filter
        end

        # Given a list of `filter_hashes` and a list of `target_field_paths`, returns a representation
        # of a set that includes all values that could be matched by the given filters.
        #
        # Essentially, this method guarantees that the following pseudo code is always satisfied:
        #
        # ``` ruby
        # filter_value_set = extract_filter_value_set(filter_hashes, target_field_paths)
        # Datastore.all_documents_matching(filter_hashes).each do |document|
        #   target_field_paths.each do |field_path|
        #     expect(filter_value_set).to include(document.value_at(field_path))
        #   end
        # end
        # ```
        def extract_filter_value_set(filter_hashes, target_field_paths)
          # We union the filter values together in cases where we have multiple target field paths
          # to make sure we cover all the values we need to. We generally do not have multiple
          # `target_field_paths` except for specialized cases, such as when searching multiple
          # indices in one query, where those indices are configured to use differing `routing_field_paths`.
          # In such a situation we must use the set union of values. Remember: including additional
          # routing values causes no adverse behavior (although it may introduce an inefficiency)
          # but if we fail to route to a shard that contains a matching document, the search results
          # will be incorrect.
          value_set = map_reduce_sets(target_field_paths, :union, negate: false) do |target_field_path|
            filter_value_set_for_target_field_path(target_field_path, filter_hashes)
          end

          return nil if (_ = value_set) == UnboundedSetWithExclusions
          _ = value_set
        end

        private

        # Determines a set of filter values for one of our `target_field_paths`,
        # based on a list of `filter_hashes`.
        def filter_value_set_for_target_field_path(target_field_path, filter_hashes)
          # Pre-split the `target_field_path` to make it easy to compare as an array,
          # since we build up the `traversed_field_path_parts` as an array as we recurse. We do this here
          # outside the `map_reduce_sets` block below so we only do it once instead of N times.
          target_field_path_parts = target_field_path.split(".")

          # Here we intersect the filter value set, because when we have multiple `filter_hashes`,
          # the filters are ANDed together. Only documents that match ALL the filters will be
          # returned. Therefore, we want the intersection of filter value sets.
          map_reduce_sets(filter_hashes, :intersection, negate: false) do |filter_hash|
            filter_value_set_for_filter_hash(filter_hash, target_field_path_parts, negate: false)
          end
        end

        # Determines the set of filter values for one of our `target_field_paths` values and one
        # `filter_hash` from a list of filter hashes. Note that this method is called recursively,
        # with `traversed_field_path_parts` as an accumulator that accumulates that path to a nested
        # field we are filtering on.
        def filter_value_set_for_filter_hash(filter_hash, target_field_path_parts, traversed_field_path_parts = [], negate:)
          # Here we intersect the filter value sets because when we have multiple entries in a filter hash,
          # the filters are ANDed together. Only documents that match ALL the filters will be
          # returned. Therefore, we want the intersection of filter value sets.
          map_reduce_sets(filter_hash, :intersection, negate: negate) do |key, value|
            filter_value_set_for_filter_hash_entry(key, value, target_field_path_parts, traversed_field_path_parts, negate: negate)
          end
        end

        # Determines the set of filter values for one of our `target_field_paths` and one
        # entry from one `filter_hash`. The key/value pair from a single entry is passed as the
        # first two arguments. Depending on where we are at in recursing through the nested structure,
        # the key could identify either a field we are filtering on or a filtering operator to apply
        # to a particular field.
        def filter_value_set_for_filter_hash_entry(field_or_op, filter_value, target_field_path_parts, traversed_field_path_parts, negate:)
          if filter_value.nil?
            # Any filter with a `nil` value is effectively treated as `true` by our filtering logic, so we need
            # to return our `@all_values_set` to indicate this filter matches all documents.
            @all_values_set
          elsif field_or_op == @schema_names.not
            filter_value_set_for_filter_hash(filter_value, target_field_path_parts, traversed_field_path_parts, negate: !negate)
          elsif filter_value.is_a?(::Hash)
            # the only time `value` is a hash is when `field_or_op` is a field name.
            # In that case, `value` is a hash of filters that apply to that field.
            filter_value_set_for_filter_hash(filter_value, target_field_path_parts, traversed_field_path_parts + [field_or_op], negate: negate)
          elsif field_or_op == @schema_names.any_of
            filter_value_set_for_any_of(filter_value, target_field_path_parts, traversed_field_path_parts, negate: negate)
          elsif target_field_path_parts == traversed_field_path_parts
            set = filter_value_set_for_field_filter(field_or_op, filter_value)
            negate ? set.negate : set
          else
            # Otherwise, we have no information in this clause. The set is unbounded, and may have exclusions.
            UnboundedSetWithExclusions
          end
        end

        # Determines the set of filter values for an `any_of` clause, which is used for ORing multiple filters together.
        def filter_value_set_for_any_of(filter_hashes, target_field_path_parts, traversed_field_path_parts, negate:)
          # Here we treat `any_of: []` as matching no values.
          if filter_hashes.empty?
            return negate ? @all_values_set : @empty_set
          end

          # Here we union the filter value sets because `any_of` represents an OR. If we can determine specific
          # filter values for all `any_of` clauses, we will OR them together. Alternately, if we cannot
          # determine specific filter values for any clauses, we will union `@all_values_set`,
          # which will result in a return value of `@all_values_set`. This is correct because if there
          # is an `any_of` clause that does not match on the `target_field_path_parts` then the filter
          # excludes no documents on the basis of the target filter.
          map_reduce_sets(filter_hashes, :union, negate: negate) do |filter_hash|
            filter_value_set_for_filter_hash(filter_hash, target_field_path_parts, traversed_field_path_parts, negate: negate)
          end
        end

        # Determines the set of filter values for a single filter on a single field.
        def filter_value_set_for_field_filter(filter_op, filter_value)
          operator_name = @schema_names.canonical_name_for(filter_op)
          @build_set_for_filter.call(operator_name, filter_value) || UnboundedSetWithExclusions
        end

        # Maps over the provided `collection` by applying the given `map_transform`
        # (which must transform a collection entry to an instance of our set representation), then reduces
        # the resulting collection to a single set value. `reduction` will be either `:union` or `:intersection`.
        #
        # If the collection is empty, we return `@all_values_set` because it's the only "safe" value
        # we can return. We don't have any information that would allow us to limit the set of filter
        # values in any way.
        def map_reduce_sets(collection, reduction, negate:, &map_transform)
          return @all_values_set if collection.empty?

          # In the case where `negate` is true (`not` is present somewhere in the filtering expression),
          # we negate the reduction operator. Utilizing De Morgan’s Law (¬(A ∪ B) <-> (¬A) ∩ (¬B)),
          # the negation of the union of two sets is the intersection of the negation of each set (the negation
          # of each set is the difference between @all_values_set and the given set)--and vice versa.
          reduction = REDUCTION_INVERSIONS.fetch(reduction) if negate

          collection.map(&map_transform).reduce do |s1, s2|
            receiver, argument = ((_ = s2) == UnboundedSetWithExclusions) ? [s2, s1] : [s1, s2]
            (reduction == :union) ? receiver.union(argument) : receiver.intersection(argument)
          end
        end

        REDUCTION_INVERSIONS = {union: :intersection, intersection: :union}

        # This minimal set implementation is used for otherwise unrepresentable cases. We use it when
        # a filter on a `target_field_path` uses an inequality like:
        #
        #     {field: {gt: "abc"}}
        #
        # In a case like that, the set is unbounded (there's an infinite number of values that are greater
        # than `"abc"`...), but it's not `@all_values_set`--since it's based on an inequality, there are
        # _some_ values that are excluded from the set. We also can't represent this case with an
        # `all_values_except(...)` set implementation because the set of exclusions is also unbounded!
        #
        # When our filter value extraction results in this set, we cannot limit what shards or indices we must hit based
        # on the filters.
        module UnboundedSetWithExclusions
          def self.intersection(other)
            # Technically, the accurate intersection would be `other - values_of(self)` but as we don't have
            # any known values from this unbounded set, we just return `other`. It's OK to include extra values
            # in the set (we'll search additional shards or indices) but not OK to fail to include necessary values
            # in the set (we'd avoid searching a shard that may have matching documents) so we err on the side of
            # including more values.
            other
          end

          def self.union(other)
            # Since our set here is unbounded, the resulting union is also unbounded.
            self
          end

          def self.negate
            # The negation of an `UnboundedSetWithExclusions` is still an `UnboundedSetWithExclusions`. While it would flip
            # which values are in or out of the set, this object is still the representation in our data model for that case.
            self
          end
        end

        private_constant :UnboundedSetWithExclusions
      end
    end
  end
end
