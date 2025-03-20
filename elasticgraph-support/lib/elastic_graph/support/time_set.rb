# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Support
    # Models a set of `::Time` objects, but does so using one or more `::Range` objects.
    # This is done so that we can support unbounded sets (such as "all times after midnight
    # on date X").
    #
    # Internally, this is a simple wrapper around a set of `::Range` objects. Those ranges take
    # a few different forms:
    #
    # - ALL: a range with no bounds, which implicitly contains all `::Time`s. (It's like the
    #   integer set from negative to positive infinity).
    # - An open range: a range with only an upper or lower bound (but not the other).
    # - A closed range: a range with an upper and lower bound.
    # - An empty range: a range that contains no `::Time`s, by virtue of its bounds having no overlap.
    #
    # @private
    class TimeSet < ::Data.define(:ranges)
      # Factory method to construct a `TimeSet` using a range with the given bounds.
      def self.of_range(gt: nil, gte: nil, lt: nil, lte: nil)
        if gt && gte
          raise ArgumentError, "TimeSet got two lower bounds, but can have only one (gt: #{gt.inspect}, gte: #{gte.inspect})"
        end

        if lt && lte
          raise ArgumentError, "TimeSet got two upper bounds, but can have only one (lt: #{lt.inspect}, lte: #{lte.inspect})"
        end

        # To be able to leverage Ruby's Range class, we need to convert to the "inclusive" ("or equal")
        # form. This cuts down on the number of test cases we need to write and also Ruby's range lets
        # you control whether the end of a range is inclusive or exclusive, but doesn't let you control
        # the beginning of the range.
        #
        # This is safe to do because our datastores only work with `::Time`s at millisecond granularity,
        # so `> t` is equivalent to `>= (t + 1ms)` and `< t` is equivalent to `<= (t - 1ms)`.
        lower_bound = gt&.+(CONSECUTIVE_TIME_INCREMENT) || gte
        upper_bound = lt&.-(CONSECUTIVE_TIME_INCREMENT) || lte

        of_range_objects(_ = [RangeFactory.build_non_empty(lower_bound, upper_bound)].compact)
      end

      # Factory method to construct a `TimeSet` from a collection of `::Time` objects.
      # Internally we convert it to a set of `::Range` objects, one per unique time.
      def self.of_times(times)
        of_range_objects(times.map { |t| ::Range.new(t, t) })
      end

      # Factory method to construct a `TimeSet` from a previously built collection of
      # ::Time ranges. Mostly used internally by `TimeSet` and in tests.
      def self.of_range_objects(range_objects)
        # Use our singleton EMPTY or ALL instances if we can to save on memory.
        return EMPTY if range_objects.empty?
        first_range = _ = range_objects.first
        return ALL if first_range.begin.nil? && first_range.end.nil?

        new(range_objects)
      end

      # Returns a new `TimeSet` containing `::Time`s common to this set and `other_set`.
      def intersection(other_set)
        # Here we rely on the distributive and commutative properties of set algebra:
        #
        # https://en.wikipedia.org/wiki/Algebra_of_sets
        # A ∩ (B ∪ C) = (A ∩ B) ∪ (A ∩ C) (distributive property)
        #       A ∩ B = B ∩ A             (commutative property)
        #
        # We can combine these properties to see how the intersection of sets of ranges would work:
        #          (A₁ ∪ A₂)        ∩        (B₁ ∪ B₂)
        # =        ((A₁ ∪ A₂) ∩ B₁) ∪ ((A₁ ∪ A₂) ∩ B₂)        (expanding based on distributive property)
        # =        (B₁ ∩ (A₁ ∪ A₂)) ∪ (B₂ ∩ (A₁ ∪ A₂))        (rearranging based on commutative property)
        # = ((B₁ ∩ A₁) ∪ (B₁ ∩ A₂)) ∪ ((B₂ ∩ A₁) ∪ (B₂ ∩ A₂)) (expanding based on distributive property)
        # =  (B₁ ∩ A₁) ∪ (B₁ ∩ A₂)  ∪  (B₂ ∩ A₁) ∪ (B₂ ∩ A₂)  (removing excess parens)
        # = union of (intersection of each pair)
        intersected_ranges = ranges.to_a.product(other_set.ranges.to_a)
          .filter_map { |r1, r2| intersect_ranges(r1, r2) }

        TimeSet.of_range_objects(intersected_ranges)
      end

      # Returns a new `TimeSet` containing `::Time`s that are in either this set or `other_set`.
      def union(other_set)
        TimeSet.of_range_objects(ranges.union(other_set.ranges))
      end

      # Returns true if the given `::Time` is a member of this `TimeSet`.
      def member?(time)
        ranges.any? { |r| r.cover?(time) }
      end

      # Returns true if this `TimeSet` and the given one have a least one time in common.
      def intersect?(other_set)
        other_set.ranges.any? do |r1|
          ranges.any? do |r2|
            ranges_intersect?(r1, r2)
          end
        end
      end

      # Returns true if this TimeSet contains no members.
      def empty?
        ranges.empty?
      end

      # Returns a new `TimeSet` containing the difference between this `TimeSet` and the given one.
      def -(other)
        new_ranges = other.ranges.to_a.reduce(ranges.to_a) do |accum, other_range|
          accum.flat_map do |self_range|
            if ranges_intersect?(self_range, other_range)
              # Since the ranges intersect, `self_range` must be reduced some how. Depending on what kind of
              # intersection we have (e.g. exact equality, `self_range` fully inside `other_range`, `other_range`
              # fully inside `self_range`, partial overlap where `self_range` begins before `other_range`, or partial
              # overlap where `self_range` ends after `other_range`), we may have a part of `self_range` that comes
              # before `other_range`, a part of `self_range` that comes after `other_range`, both, or neither. Below
              # we build the before and after parts as candidates, but then ignore any resulting ranges that are
              # invalid, which leaves us with the correct result, without having to explicitly handle each possible case.

              # @type var candidates: ::Array[timeRange]
              candidates = []

              if (other_range_begin = other_range.begin)
                # This represents the parts of `self_range` that come _before_ `other_range`.
                candidates << Range.new(self_range.begin, other_range_begin - CONSECUTIVE_TIME_INCREMENT)
              end

              if (other_range_end = other_range.end)
                # This represents the parts of `self_range` that come _after_ `other_range`.
                candidates << Range.new(other_range_end + CONSECUTIVE_TIME_INCREMENT, self_range.end)
              end

              # While some of the ranges produced above may be invalid (due to being descending), we don't have to
              # filter them out here because `#initialize` takes care of it.
              candidates
            else
              # Since the ranges don't intersect, there is nothing to remove from `self_range`; just return it unmodified.
              [self_range]
            end
          end
        end

        TimeSet.of_range_objects(new_ranges)
      end

      def negate
        ALL - self
      end

      private

      private_class_method :new # use `of_range`, `of_times`, or `of_range_objects` instead.

      # To ensure immutability, we override this to freeze the set. For convenience, we allow the `ranges`
      # arg to be an array, and convert to a set here. In addition, we take care of normalizing to the most
      # optimal form by merging overlapping ranges here, and ignore descending ranges.
      def initialize(ranges:)
        normalized_ranges = ranges
          .reject { |r| descending_range?(r) }
          .to_set
          .then { |rs| merge_overlapping_or_adjacent_ranges(rs) }
          .freeze

        super(ranges: normalized_ranges)
      end

      # Returns true if at least one ::Time exists in both ranges.
      def ranges_intersect?(r1, r2)
        r1.cover?(r2.begin) || r1.cover?(r2.end) || r2.cover?(r1.begin) || r2.cover?(r1.end)
      end

      # The amount to add to a time to get the next consecutive time, based
      # on the level of granularity we support. According to the Elasticsearch docs[1],
      # it only supports millisecond granularity, so that's all we support:
      #
      # > Internally, dates are converted to UTC (if the time-zone is specified) and
      # > stored as a long number representing milliseconds-since-the-epoch.
      #
      # We want exact precision here, so we are avoiding using a float for this, preferring
      # to use a rational instead.
      #
      # [1] https://www.elastic.co/guide/en/elasticsearch/reference/7.15/date.html
      CONSECUTIVE_TIME_INCREMENT = Rational(1, 1000)

      # Returns true if the given ranges are adjacent with no room for any ::Time
      # objects to exist between the ranges given the millisecond granularity we operate at.
      def adjacent?(r1, r2)
        r1.end&.+(CONSECUTIVE_TIME_INCREMENT)&.==(r2.begin) || r2.end&.+(CONSECUTIVE_TIME_INCREMENT)&.==(r1.begin) || false
      end

      # Combines the given ranges into a new range that only contains the common subset of ::Time objects.
      # Returns `nil` if there is no intersection.
      def intersect_ranges(r1, r2)
        RangeFactory.build_non_empty(
          [r1.begin, r2.begin].compact.max,
          [r1.end, r2.end].compact.min
        )
      end

      # Helper method that attempts to merge the given set of ranges into an equivalent
      # set that contains fewer ranges in it but covers the same set of ::Time objects.
      # As an example, consider these two ranges:
      #
      # - 2020-05-01 to 2020-07-01
      # - 2020-06-01 to 2020-08-01
      #
      # These two ranges can safely be merged into a single range of 2020-05-01 to 2020-08-01.
      # Technically speaking, this is not required; we can just return a TimeSet containing
      # multiple ranges. However, the goal of a TimeSet is to represent a set of Time objects
      # as minimally as possible, and to that end it is useful to merge ranges when possible.
      # While it adds a bit of complexity to merge ranges like this, it'll simplify future
      # calculations involving a TimeSet.
      def merge_overlapping_or_adjacent_ranges(all_ranges)
        # We sometimes have to apply this merge algorithm multiple times in order to fully merge
        # the ranges into their minimal form. For example, consider these three ranges:
        #
        # - 2020-05-01 to 2020-07-01
        # - 2020-06-01 to 2020-09-01
        # - 2020-08-01 to 2020-10-01
        #
        # Ultimately, we can merge these into a single range of 2020-05-01 to 2020-10-01, but
        # our algorithm isn't able to do that in a single pass. On the first pass it'll produce
        # two merged ranges (2020-05-01 to 2020-09-01 and 2020-06-01 to 2020-10-01); after we
        # apply the algorithm again it is then able to produce the final merged range.
        # Since we can't predict how many iterations it'll take, we loop here, and break as
        # soon as there is no more progress to be made.
        #
        # While we can't predice how many iterations it'll take, we can put an upper bound on it:
        # it should take no more than `all_ranges.size` times, because every iteration should shrink
        # `all_ranges` by at least one element--if not, that iteration didn't make any progress
        # (and we're done anyway).
        all_ranges.size.times do
          # Given our set of ranges, any range is potentially mergeable with any other range.
          # Here we determine which pairs of ranges are mergeable.
          mergeable_range_pairs = all_ranges.to_a.combination(2).select do |r1, r2|
            ranges_intersect?(r1, r2) || adjacent?(r1, r2)
          end

          # If there are no mergeable pairs, we're done!
          return all_ranges if mergeable_range_pairs.empty?

          # For each pair of mergeable ranges, build a merged range.
          merged_ranges = mergeable_range_pairs.filter_map do |r1, r2|
            RangeFactory.build_non_empty(
              nil_or(:min, from: [r1.begin, r2.begin]),
              nil_or(:max, from: [r1.end, r2.end])
            )
          end

          # Update `all_ranges` based on the merges performed so far.
          unmergeable_ranges = all_ranges - mergeable_range_pairs.flatten
          all_ranges = unmergeable_ranges.union(_ = merged_ranges)
        end

        all_ranges
      end

      # Helper method for `merge_overlapping_or_adjacent_ranges` used to return the most "lenient" range boundary value.
      # `nil` is used for a beginless or endless range, so we return that if available; otherwise
      # we apply `min_or_max`.`
      def nil_or(min_or_max, from:)
        return nil if from.include?(nil)
        from.public_send(min_or_max)
      end

      def descending_range?(range)
        # If either edge is `nil` it cannot be descending.
        return false if (range_begin = range.begin).nil?
        return false if (range_end = range.end).nil?

        # Otherwise we just compare the edges to determine if it's descending.
        range_begin > range_end
      end

      # An instance in which all `::Time`s fit.
      ALL = new([::Range.new(nil, nil)])
      # Singleton instance that's empty.
      EMPTY = new([])

      module RangeFactory
        # Helper method for building a range from the given bounds. Returns either
        # a built range, or, if the given bounds produce an empty range, returns nil.
        def self.build_non_empty(lower_bound, upper_bound)
          if lower_bound.nil? || upper_bound.nil? || lower_bound <= upper_bound
            ::Range.new(lower_bound, upper_bound)
          end
        end
      end
    end
  end
end
