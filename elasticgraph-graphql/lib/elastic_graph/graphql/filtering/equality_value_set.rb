# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Filtering
      # A set that can represent either a specific list of values or all values except a specific
      # list, with support for common set operations (union, intersection, negation). In contrast
      # to other set implementations that work with `FilterValueSetExtractor`, this only works with
      # `equal_to_any_of` filtering (hence the `EqualityValueSet` name).
      class EqualityValueSet < Data.define(:type, :values)
        # `Data.define` provides the following methods:
        # @dynamic initialize, type, values, with

        def self.of(values)
          new(:inclusive, values.to_set)
        end

        def self.of_all_except(values)
          new(:exclusive, values.to_set)
        end

        ALL = of_all_except([])
        EMPTY = of([])

        def intersection(other)
          if inclusive? && other.inclusive?
            # Since both sets are inclusive, we can just delegate to `Set#intersection` here.
            EqualityValueSet.of(values.intersection(other.values))
          elsif exclusive? && other.exclusive?
            # Since both sets are exclusive, we need to return an exclusive set of the union of the
            # excluded values. For example, when dealing with positive integers:
            #
            #   s1 = EqualityValueSet.of_all_except([1, 2, 3]) # > 3
            #   s2 = EqualityValueSet.of_all_except([3, 4, 5]) # 1, 2, > 5
            #
            #   s3 = s1.intersection(s2)
            #
            # Here s3 would be all values > 5 (the same as `EqualityValueSet.of_all_except([1, 2, 3, 4, 5])`)
            EqualityValueSet.of_all_except(values.union(other.values))
          else
            # Since one set is inclusive and one set is exclusive, we need to return an inclusive set of
            # `included_values - excluded_values`. For example, when dealing with positive integers:
            #
            #   s1 = EqualityValueSet.of([1, 2, 3]) # 1, 2, 3
            #   s2 = EqualityValueSet.of_all_except([3, 4, 5]) # 1, 2, > 5
            #
            #   s3 = s1.intersection(s2)
            #
            # Here s3 would be just `1, 2`.
            included_values, excluded_values = get_included_and_excluded_values(other)
            EqualityValueSet.of(included_values - excluded_values)
          end
        end

        def union(other)
          if inclusive? && other.inclusive?
            # Since both sets are inclusive, we can just delegate to `Set#union` here.
            EqualityValueSet.of(values.union(other.values))
          elsif exclusive? && other.exclusive?
            # Since both sets are exclusive, we need to return an exclusive set of the intersection of the
            # excluded values. For example, when dealing with positive integers:
            #
            #   s1 = EqualityValueSet.of_all_except([1, 2, 3]) # > 3
            #   s2 = EqualityValueSet.of_all_except([3, 4, 5]) # 1, 2, > 5
            #
            #   s3 = s1.union(s2)
            #
            # Here s3 would be all 1, 2, > 3 (the same as `EqualityValueSet.of_all_except([3])`)
            EqualityValueSet.of_all_except(values.intersection(other.values))
          else
            # Since one set is inclusive and one set is exclusive, we need to return an exclusive set of
            # `excluded_values - included_values`. For example, when dealing with positive integers:
            #
            #   s1 = EqualityValueSet.of([1, 2, 3]) # 1, 2, 3
            #   s2 = EqualityValueSet.of_all_except([3, 4, 5]) # 1, 2, > 5
            #
            #   s3 = s1.union(s2)
            #
            # Here s3 would be 1, 2, 3, > 5 (the same as `EqualityValueSet.of_all_except([4, 5])`)
            included_values, excluded_values = get_included_and_excluded_values(other)
            EqualityValueSet.of_all_except(excluded_values - included_values)
          end
        end

        def negate
          with(type: INVERTED_TYPES.fetch(type))
        end

        INVERTED_TYPES = {inclusive: :exclusive, exclusive: :inclusive}

        def inclusive?
          type == :inclusive
        end

        def exclusive?
          type == :exclusive
        end

        private

        def get_included_and_excluded_values(other)
          inclusive? ? [values, other.values] : [other.values, values]
        end
      end
    end
  end
end
