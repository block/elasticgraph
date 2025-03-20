# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/time_set"
require "time"

module ElasticGraph
  module Support
    # Note: the tests in this file were inherited from an earlier implementation where `gt/gte` and `lt/lte`
    # were not normalized to the same representation, and as such there are lots of cases in the tests
    # covering both. Technically, we don't really need these (and I wouldn't write them from scratch if
    # we didn't already have them), but it seems worth keeping. Don't feel like you have to cover all cases
    # like that in new tests, though.
    RSpec.describe TimeSet do
      describe ".of_range" do
        it "prevents `gt` and `gte` being used together as that would create two lower builds" do
          expect {
            TimeSet.of_range(gt: ::Time.at(1), gte: ::Time.at(2))
          }.to raise_error ArgumentError, a_string_including("two lower bound")
        end

        it "prevents `lt` and `lte` being used together as that would create two upper builds" do
          expect {
            TimeSet.of_range(lt: ::Time.at(1000), lte: ::Time.at(2000))
          }.to raise_error ArgumentError, a_string_including("two upper bounds")
        end

        it "can build an endless range" do
          time_set = TimeSet.of_range(gte: ::Time.iso8601("2021-03-12T12:30:00Z"))
          expect(time_set.ranges).to contain_exactly(::Time.iso8601("2021-03-12T12:30:00Z")..)
        end

        it "can build a beginless range" do
          time_set = TimeSet.of_range(lte: ::Time.iso8601("2021-03-12T12:30:00Z"))
          expect(time_set.ranges).to contain_exactly(..::Time.iso8601("2021-03-12T12:30:00Z"))
        end

        it "normalizes `gt` to its equivalent `gte` form (based on datastore millisecond time granularity)" do
          time_set = TimeSet.of_range(gt: ::Time.iso8601("2021-03-12T12:30:00Z"))
          expect(time_set.ranges).to contain_exactly(::Time.iso8601("2021-03-12T12:30:00.001Z")..)
        end

        it "normalizes `lt` to its equivalent `lte` form (based on datastore millisecond time granularity)" do
          time_set = TimeSet.of_range(lt: ::Time.iso8601("2021-03-12T12:30:00Z"))
          expect(time_set.ranges).to contain_exactly(..::Time.iso8601("2021-03-12T12:29:59.999Z"))
        end

        it "ignores a descending range as a set of times greater than a timestamp that comes after the less than timestamp is empty" do
          time_set = TimeSet.of_range(gte: ::Time.iso8601("2020-07-01T00:00:00Z"), lt: ::Time.iso8601("2020-05-01T00:00:00Z"))
          expect(time_set).to be(TimeSet::EMPTY)
        end
      end

      describe ".of_range_objects" do
        it "merges overlapping ranges to normalize to a more efficient (but equivalent) representation" do
          time_set = TimeSet.of_range_objects([
            ::Time.iso8601("2020-05-01T00:00:00Z")..::Time.iso8601("2020-07-01T00:00:00Z"),
            ::Time.iso8601("2020-06-01T00:00:00Z")..::Time.iso8601("2020-09-01T00:00:00Z"),
            ::Time.iso8601("2020-08-01T00:00:00Z")..::Time.iso8601("2020-10-01T00:00:00Z")
          ])

          expect(time_set).to eq(set_of_range(gte: "2020-05-01T00:00:00Z", lte: "2020-10-01T00:00:00Z"))
        end

        it "merges adjacent ranges (e.g. with no gap between) to a more efficient (but equivalent) representation" do
          time_set = set_of_ranges(
            {gte: "2020-05-01T00:00:00Z", lte: "2020-06-30T23:59:59.999Z"},
            {gte: "2020-07-01T00:00:00Z", lt: "2020-09-01T00:00:00Z"}
          )

          expect(time_set).to eq(set_of_range(gte: "2020-05-01T00:00:00Z", lt: "2020-09-01T00:00:00Z"))
        end

        it "ignores descending ranges as a set of times greater than a timestamp that comes after the less than timestamp is empty" do
          # Note: we must avoid using `set_of_ranges` here because it leverages `TimeSet.of_range` which already had
          # some handling for this; here we use `TimeSet.of_range_objects` directly to verify how it works.
          time_set = TimeSet.of_range_objects([
            ::Time.iso8601("2020-07-01T00:00:00Z")..::Time.iso8601("2020-05-01T00:00:00Z"),
            ::Time.iso8601("2020-10-01T00:00:00Z")..::Time.iso8601("2020-08-01T00:00:00Z"),
            ::Time.iso8601("2021-02-01T00:00:00Z")..::Time.iso8601("2021-04-01T00:00:00Z")
          ])

          expect(time_set).to eq(set_of_range(gte: "2021-02-01T00:00:00Z", lte: "2021-04-01T00:00:00Z"))
        end
      end

      describe ".of_times" do
        it "returns the empty set when given an empty list of time values" do
          time_set = TimeSet.of_times([])
          expect(time_set).to be_empty
        end

        it "returns a set of a single range that only allows the single timestamp value when given a single time" do
          time = ::Time.iso8601("2021-03-12T12:30:00Z")
          time_set = TimeSet.of_times([time])

          expect(time_set).not_to be_empty
          expect(time_set.member?(time)).to be true
          expect(time_set.member?(time + TimeSet::CONSECUTIVE_TIME_INCREMENT)).to be false
          expect(time_set.member?(time - TimeSet::CONSECUTIVE_TIME_INCREMENT)).to be false
          expect(time_set.ranges).to contain_exactly(time..time)
        end

        it "converts multiple times into multiple ranges, removing duplicates in the process" do
          time1 = ::Time.iso8601("2021-03-12T12:30:00Z")
          time2 = ::Time.iso8601("2021-04-12T12:30:00Z")
          time3 = ::Time.iso8601("2021-05-12T12:30:00Z")
          time_set = TimeSet.of_times([time1, time2, time1, time3, time1])

          expect(time_set.member?(time1)).to be true
          expect(time_set.member?(time2)).to be true
          expect(time_set.member?(time3)).to be true
          expect(time_set.member?(time1 + TimeSet::CONSECUTIVE_TIME_INCREMENT)).to be false
          expect(time_set.member?(time1 - TimeSet::CONSECUTIVE_TIME_INCREMENT)).to be false
          expect(time_set.member?(time2 + TimeSet::CONSECUTIVE_TIME_INCREMENT)).to be false
          expect(time_set.member?(time2 - TimeSet::CONSECUTIVE_TIME_INCREMENT)).to be false
          expect(time_set.member?(time3 + TimeSet::CONSECUTIVE_TIME_INCREMENT)).to be false
          expect(time_set.member?(time3 - TimeSet::CONSECUTIVE_TIME_INCREMENT)).to be false

          expect(time_set.ranges).to contain_exactly(
            time1..time1,
            time2..time2,
            time3..time3
          )
        end
      end

      describe "#intersection" do
        it "intersects two overlapping closed ranges by shrinking them to the overlapping portion" do
          s1 = set_of_range(gte: "2021-01-01T00:00:00Z", lt: "2021-03-01T00:00:00Z")
          s2 = set_of_range(gte: "2021-02-01T00:00:00Z", lt: "2021-09-01T00:00:00Z")

          expect_intersection(s1, s2) do
            set_of_range(gte: "2021-02-01T00:00:00Z", lt: "2021-03-01T00:00:00Z")
          end
        end

        it "intersects two closed ranges where one is a subset of the other by returning the inner subset" do
          s1 = set_of_range(gte: "2021-01-01T00:00:00Z", lt: "2021-09-01T00:00:00Z")
          s2 = set_of_range(gte: "2021-02-01T00:00:00Z", lt: "2021-03-01T00:00:00Z")

          expect_intersection(s1, s2) { s2 }
        end

        it "intersects two beginless ranges by shrinking the upper bound to the lower of the two upper bounds" do
          s1 = set_of_range(lt: "2021-03-01T00:00:00Z")
          s2 = set_of_range(lt: "2021-09-01T00:00:00Z")

          expect_intersection(s1, s2) do
            set_of_range(lt: "2021-03-01T00:00:00Z")
          end
        end

        it "intersects two endless ranges by shrinking the lower bound to the higher of the two lower bounds" do
          s1 = set_of_range(gte: "2021-03-01T00:00:00Z")
          s2 = set_of_range(gte: "2021-09-01T00:00:00Z")

          expect_intersection(s1, s2) do
            set_of_range(gte: "2021-09-01T00:00:00Z")
          end
        end

        it "intersects an overlapping beginless range and an endless range by using the finite bound from each range" do
          s1 = set_of_range(gte: "2021-03-01T00:00:00Z")
          s2 = set_of_range(lt: "2021-09-01T00:00:00Z")

          expect_intersection(s1, s2) do
            set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-09-01T00:00:00Z")
          end
        end

        it "returns an empty set when two bounded ranges have no overlapping portion" do
          s1 = set_of_range(gte: "2021-01-01T00:00:00Z", lt: "2021-03-01T00:00:00Z")
          s2 = set_of_range(gte: "2021-04-01T00:00:00Z", lt: "2021-09-01T00:00:00Z")

          expect_intersection(s1, s2) do
            TimeSet::EMPTY
          end
        end

        it "returns an empty set when a beginless and an endless range have no overlapping portion" do
          s1 = set_of_range(lt: "2021-03-01T00:00:00Z")
          s2 = set_of_range(gte: "2021-04-01T00:00:00Z")

          expect_intersection(s1, s2) do
            TimeSet::EMPTY
          end
        end

        it "returns an empty set when two ranges have the same boundary but zero overlap" do
          s1 = set_of_range(lt: "2021-04-01T00:00:00Z")
          s2 = set_of_range(gte: "2021-04-01T00:00:00Z")

          expect_intersection(s1, s2) do
            TimeSet::EMPTY
          end
        end

        it "returns a set of a single time when two ranges have the same boundary with only that single time value as the overlap" do
          s1 = set_of_range(lte: "2021-04-01T00:00:00Z")
          s2 = set_of_range(gte: "2021-04-01T00:00:00Z")

          expect_intersection(s1, s2) do
            set_of_times("2021-04-01T00:00:00Z")
          end
        end

        it "returns an empty set when either set is empty" do
          s1 = set_of_range(gte: "2021-01-01T00:00:00Z", lt: "2021-03-01T00:00:00Z")

          expect_intersection(s1, TimeSet::EMPTY) do
            TimeSet::EMPTY
          end
        end

        it "returns an empty set when both sets are empty" do
          expect_intersection(TimeSet::EMPTY, TimeSet::EMPTY) do
            TimeSet::EMPTY
          end
        end

        it "intersects multiple single times and a range to just those times that fall within the range" do
          s1 = set_of_times("2021-02-15T00:00:00Z", "2021-03-15T00:00:00Z", "2021-04-15T00:00:00Z", "2021-05-15T00:00:00Z")
          s2 = set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-05-01T00:00:00Z")

          expect_intersection(s1, s2) do
            set_of_times("2021-03-15T00:00:00Z", "2021-04-15T00:00:00Z")
          end
        end

        it "can intersect multiple ranges with multiple ranges" do
          s1 = set_of_ranges(
            {gte: "2020-01-01T00:00:00Z", lte: "2020-03-01T00:00:00Z"},
            {gte: "2020-05-01T00:00:00Z", lte: "2020-06-01T00:00:00Z"},
            {gte: "2020-09-01T00:00:00Z", lte: "2020-11-01T00:00:00Z"},
            {gte: "2021-01-01T00:00:00Z", lte: "2021-02-01T00:00:00Z"}
          )

          s2 = set_of_ranges(
            {gte: "2020-02-01T00:00:00Z", lte: "2020-05-01T00:00:00Z"},
            {gte: "2020-06-01T00:00:00Z", lte: "2020-09-01T00:00:00Z"}
          )

          expect_intersection(s1, s2) do
            set_of_ranges(
              {gte: "2020-02-01T00:00:00Z", lte: "2020-03-01T00:00:00Z"},
              {gte: "2020-05-01T00:00:00Z", lte: "2020-05-01T00:00:00Z"},
              {gte: "2020-06-01T00:00:00Z", lte: "2020-06-01T00:00:00Z"},
              {gte: "2020-09-01T00:00:00Z", lte: "2020-09-01T00:00:00Z"}
            )
          end
        end

        def expect_intersection(s1, s2)
          actual1 = s1.intersection(s2)
          actual2 = s2.intersection(s1)

          expect(actual1).to eq(actual2)
          expect(actual1).to eq(yield)
        end
      end

      describe "#union" do
        it "unions two overlapping closed ranges by growing them to the outer bounds" do
          s1 = set_of_range(gte: "2021-01-01T00:00:00Z", lt: "2021-03-01T00:00:00Z")
          s2 = set_of_range(gte: "2021-02-01T00:00:00Z", lt: "2021-09-01T00:00:00Z")

          expect_union(s1, s2) do
            set_of_range(gte: "2021-01-01T00:00:00Z", lt: "2021-09-01T00:00:00Z")
          end
        end

        it "unions two closed ranges where one is a subset of the other by returning the outer set" do
          s1 = set_of_range(gte: "2021-01-01T00:00:00Z", lt: "2021-09-01T00:00:00Z")
          s2 = set_of_range(gte: "2021-02-01T00:00:00Z", lt: "2021-03-01T00:00:00Z")

          expect_union(s1, s2) do
            s1
          end
        end

        it "unions two beginless ranges by growing the upper bound to the larger of the two upper bounds" do
          s1 = set_of_range(lt: "2021-03-01T00:00:00Z")
          s2 = set_of_range(lt: "2021-09-01T00:00:00Z")

          expect_union(s1, s2) do
            set_of_range(lt: "2021-09-01T00:00:00Z")
          end
        end

        it "unions two endless ranges by growing the lower bound to the lower of the two lower bounds" do
          s1 = set_of_range(gte: "2021-03-01T00:00:00Z")
          s2 = set_of_range(gte: "2021-09-01T00:00:00Z")

          expect_union(s1, s2) do
            set_of_range(gte: "2021-03-01T00:00:00Z")
          end
        end

        it "unions an overlapping beginless range and an endless range to ALL" do
          s1 = set_of_range(gte: "2021-03-01T00:00:00Z")
          s2 = set_of_range(lt: "2021-09-01T00:00:00Z")

          expect_union(s1, s2) do
            TimeSet::ALL
          end
        end

        it "returns a set containing each range when two bounded ranges have no overlapping portion" do
          s1 = set_of_range(gte: "2021-01-01T00:00:00Z", lt: "2021-03-01T00:00:00Z")
          s2 = set_of_range(gte: "2021-04-01T00:00:00Z", lt: "2021-09-01T00:00:00Z")

          expect_union(s1, s2) do
            set_of_ranges(
              {gte: "2021-01-01T00:00:00Z", lt: "2021-03-01T00:00:00Z"},
              {gte: "2021-04-01T00:00:00Z", lt: "2021-09-01T00:00:00Z"}
            )
          end
        end

        it "returns an set containing each range when a beginless and an endless range have no overlapping portion" do
          s1 = set_of_range(gte: "2021-09-01T00:00:00Z")
          s2 = set_of_range(lt: "2021-03-01T00:00:00Z")

          expect_union(s1, s2) do
            set_of_ranges(
              {gte: "2021-09-01T00:00:00Z"},
              {lt: "2021-03-01T00:00:00Z"}
            )
          end
        end

        it "merges two ranges into one when they have the same boundary and only with only that single time value as the overlap" do
          s1 = set_of_range(gte: "2021-01-01T00:00:00Z", lte: "2021-04-01T00:00:00Z")
          s2 = set_of_range(gte: "2021-04-01T00:00:00Z", lt: "2021-10-01T00:00:00Z")

          expect_union(s1, s2) do
            set_of_range(gte: "2021-01-01T00:00:00Z", lt: "2021-10-01T00:00:00Z")
          end
        end

        it "merges two ranges into one when they have the same boundary but zero overlap" do
          s1 = set_of_range(gte: "2021-01-01T00:00:00Z", lt: "2021-04-01T00:00:00Z")
          s2 = set_of_range(gte: "2021-04-01T00:00:00Z", lt: "2021-10-01T00:00:00Z")

          expect_union(s1, s2) do
            set_of_range(gte: "2021-01-01T00:00:00Z", lt: "2021-10-01T00:00:00Z")
          end
        end

        it "returns the other set when one set is empty" do
          s1 = set_of_range(gte: "2021-01-01T00:00:00Z", lt: "2021-03-01T00:00:00Z")

          expect_union(s1, TimeSet::EMPTY) do
            s1
          end
        end

        it "returns an empty set when both sets are empty" do
          expect_union(TimeSet::EMPTY, TimeSet::EMPTY) do
            TimeSet::EMPTY
          end
        end

        it "can union multiple ranges with multiple ranges properly" do
          s1 = set_of_ranges(
            {gte: "2020-01-01T00:00:00Z", lte: "2020-03-01T00:00:00Z"},
            {gte: "2020-05-01T00:00:00Z", lte: "2020-06-01T00:00:00Z"},
            {gte: "2020-09-01T00:00:00Z", lte: "2020-11-01T00:00:00Z"},
            {gte: "2021-01-01T00:00:00Z", lte: "2021-02-01T00:00:00Z"}
          )

          s2 = set_of_ranges(
            {gte: "2020-02-01T00:00:00Z", lte: "2020-05-01T00:00:00Z"},
            {gte: "2020-06-01T00:00:00Z", lte: "2020-09-01T00:00:00Z"}
          )

          expect_union(s1, s2) do
            set_of_ranges(
              {gte: "2020-01-01T00:00:00Z", lte: "2020-11-01T00:00:00Z"},
              {gte: "2021-01-01T00:00:00Z", lte: "2021-02-01T00:00:00Z"}
            )
          end
        end

        def expect_union(s1, s2)
          actual1 = s1.union(s2)
          actual2 = s2.union(s1)

          expect(actual1).to eq(actual2)
          expect(actual1).to eq(yield)
        end
      end

      describe "#member?" do
        let(:min_time) { ::Time.iso8601("0000-01-01T00:00:00Z") }
        let(:max_time) { ::Time.iso8601("9999-12-31T23:59:59.999Z") }

        context "for the ALL set" do
          it "returns true regardless of the timestamp" do
            expect(TimeSet::ALL.member?(min_time)).to be true
            expect(TimeSet::ALL.member?(::Time.now)).to be true
            expect(TimeSet::ALL.member?(max_time)).to be true
          end
        end

        context "for a set of a range with no upper bound" do
          it "returns true only for timestamps on or after a >= lower bound" do
            range = set_of_range(gte: "2021-05-12T08:00:00Z")

            expect(range.member?(::Time.iso8601("2021-05-14T12:30:00Z"))).to be true
            expect(range.member?(max_time)).to be true
            expect(range.member?(::Time.iso8601("2021-05-12T08:00:00Z"))).to be true

            expect(range.member?(::Time.iso8601("2021-05-12T07:59:59.999Z"))).to be false
            expect(range.member?(min_time)).to be false
          end

          it "returns true only for timestamps after a > lower bound" do
            range = set_of_range(gt: "2021-05-12T08:00:00Z")

            expect(range.member?(::Time.iso8601("2021-05-14T12:30:00Z"))).to be true
            expect(range.member?(max_time)).to be true

            expect(range.member?(::Time.iso8601("2021-05-12T08:00:00Z"))).to be false
            expect(range.member?(::Time.iso8601("2021-05-12T07:59:59.999Z"))).to be false
            expect(range.member?(min_time)).to be false
          end
        end

        context "for a set of a range with no lower bound" do
          it "returns true only for timestamps on or before a <= upper bound" do
            range = set_of_range(lte: "2021-05-12T08:00:00Z")

            expect(range.member?(::Time.iso8601("2021-05-10T12:30:00Z"))).to be true
            expect(range.member?(min_time)).to be true
            expect(range.member?(::Time.iso8601("2021-05-12T08:00:00Z"))).to be true

            expect(range.member?(::Time.iso8601("2021-05-12T08:00:00.001Z"))).to be false
            expect(range.member?(max_time)).to be false
          end

          it "returns true only for timestamps before a < upper bound" do
            range = set_of_range(lt: "2021-05-12T08:00:00Z")

            expect(range.member?(::Time.iso8601("2021-05-10T12:30:00Z"))).to be true
            expect(range.member?(min_time)).to be true

            expect(range.member?(::Time.iso8601("2021-05-12T08:00:00Z"))).to be false
            expect(range.member?(::Time.iso8601("2021-05-12T08:00:00.001Z"))).to be false
            expect(range.member?(max_time)).to be false
          end
        end

        context "for a set with a range with upper and lower bounds" do
          it "returns true only for timestamps on or within the boundaries when the bounds are >= and <=" do
            range = set_of_range(gte: "2021-05-12T08:00:00Z", lte: "2021-06-12T08:00:00Z")

            expect(range.member?(::Time.iso8601("2021-05-14T12:30:00Z"))).to be true
            expect(range.member?(::Time.iso8601("2021-05-12T08:00:00Z"))).to be true
            expect(range.member?(::Time.iso8601("2021-06-12T08:00:00Z"))).to be true

            expect(range.member?(::Time.iso8601("2021-05-12T07:59:59.999Z"))).to be false
            expect(range.member?(::Time.iso8601("2021-06-12T08:00:00.001Z"))).to be false
            expect(range.member?(min_time)).to be false
            expect(range.member?(max_time)).to be false
          end

          it "returns true only for timestamps after a > lower bound" do
            range = set_of_range(gt: "2021-05-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")

            expect(range.member?(::Time.iso8601("2021-05-14T12:30:00Z"))).to be true
            expect(range.member?(::Time.iso8601("2021-05-12T08:00:00.001Z"))).to be true
            expect(range.member?(::Time.iso8601("2021-06-12T07:59:59.999Z"))).to be true

            expect(range.member?(::Time.iso8601("2021-05-12T08:00:00Z"))).to be false
            expect(range.member?(::Time.iso8601("2021-06-12T08:00:00Z"))).to be false
            expect(range.member?(min_time)).to be false
            expect(range.member?(max_time)).to be false
          end

          it "returns false for all timestamps for an empty set" do
            range = set_of_range(lt: "2021-05-12T08:00:00Z", gt: "2021-06-12T08:00:00Z", expected_empty: true)

            expect(range.member?(min_time)).to be false
            expect(range.member?(::Time.iso8601("2021-05-10T12:30:00Z"))).to be false
            expect(range.member?(::Time.iso8601("2021-05-14T12:30:00Z"))).to be false
            expect(range.member?(::Time.iso8601("2021-05-12T08:00:00.001Z"))).to be false
            expect(range.member?(::Time.iso8601("2021-06-12T07:59:59.999Z"))).to be false
            expect(range.member?(::Time.iso8601("2021-05-12T08:00:00Z"))).to be false
            expect(range.member?(::Time.iso8601("2021-06-12T08:00:00Z"))).to be false
            expect(range.member?(::Time.iso8601("2021-06-14T12:30:00Z"))).to be false
            expect(range.member?(max_time)).to be false
          end
        end
      end

      describe "#intersect?" do
        context "when one of the sets is ALL" do
          it "returns true when given any non-empty set" do
            expect(TimeSet::ALL).to intersect_with(set_of_range(gt: "2021-05-12T08:00:00Z", lt: "2021-06-12T08:00:00Z"))
            expect(TimeSet::ALL).to intersect_with(TimeSet::ALL)
            expect(TimeSet::ALL).to intersect_with(set_of_range(lt: "2021-05-12T08:00:00Z"))
          end

          it "does not intersect with an empty set" do
            expect(TimeSet::ALL).not_to intersect_with(set_of_range(lt: "2021-05-12T08:00:00Z", gt: "2021-06-12T08:00:00Z", expected_empty: true))
          end
        end

        context "when both sets have a single range that lack an upper bound" do
          it "returns true, regardless of where the bound is" do
            expect(set_of_range(lt: "2021-05-12T08:00:00Z")).to intersect_with(set_of_range(lt: "2020-05-12T08:00:00Z"))
            expect(set_of_range(lt: "2021-05-12T08:00:00Z")).to intersect_with(set_of_range(lt: "2019-05-12T08:00:00Z"))
            expect(set_of_range(lte: "2021-05-12T08:00:00Z")).to intersect_with(set_of_range(lt: "2020-05-12T08:00:00Z"))
            expect(set_of_range(lte: "2021-05-12T08:00:00Z")).to intersect_with(set_of_range(lt: "2019-05-12T08:00:00Z"))
            expect(set_of_range(lt: "2021-05-12T08:00:00Z")).to intersect_with(set_of_range(lte: "2020-05-12T08:00:00Z"))
            expect(set_of_range(lt: "2021-05-12T08:00:00Z")).to intersect_with(set_of_range(lte: "2019-05-12T08:00:00Z"))
          end
        end

        context "when both sets have a single range that lacks a lower bound" do
          it "returns true, regardless of where the bound is" do
            expect(set_of_range(gt: "2021-05-12T08:00:00Z")).to intersect_with(set_of_range(gt: "2020-05-12T08:00:00Z"))
            expect(set_of_range(gt: "2021-05-12T08:00:00Z")).to intersect_with(set_of_range(gt: "2019-05-12T08:00:00Z"))
            expect(set_of_range(gte: "2021-05-12T08:00:00Z")).to intersect_with(set_of_range(gt: "2020-05-12T08:00:00Z"))
            expect(set_of_range(gte: "2021-05-12T08:00:00Z")).to intersect_with(set_of_range(gt: "2019-05-12T08:00:00Z"))
            expect(set_of_range(gt: "2021-05-12T08:00:00Z")).to intersect_with(set_of_range(gte: "2020-05-12T08:00:00Z"))
            expect(set_of_range(gt: "2021-05-12T08:00:00Z")).to intersect_with(set_of_range(gte: "2019-05-12T08:00:00Z"))
          end
        end

        context "when both sets have a single range that has both bounds" do
          it "returns false if one comes completely before the other" do
            expect(
              set_of_range(gt: "2021-05-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            ).not_to intersect_with(
              set_of_range(gt: "2021-03-12T08:00:00Z", lt: "2021-04-12T08:00:00Z")
            )
          end

          it "returns true if they partially overlap" do
            expect(
              set_of_range(gt: "2021-04-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            ).to intersect_with(
              set_of_range(gt: "2021-03-12T08:00:00Z", lt: "2021-05-12T08:00:00Z")
            )
          end

          it "returns true if they exactly overlap" do
            expect(
              set_of_range(gt: "2021-04-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            ).to intersect_with(
              set_of_range(gt: "2021-04-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            )
          end

          it "returns true if one fits in the other" do
            expect(
              set_of_range(gt: "2021-03-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            ).to intersect_with(
              set_of_range(gt: "2021-04-12T08:00:00Z", lt: "2021-05-12T08:00:00Z")
            )
          end

          it "returns the correct value if they share a boundary" do
            expect(
              set_of_range(gt: "2021-03-12T08:00:00Z", lt: "2021-05-12T08:00:00Z")
            ).not_to intersect_with(
              set_of_range(gt: "2021-05-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            )

            expect(
              set_of_range(gt: "2021-03-12T08:00:00Z", lte: "2021-05-12T08:00:00Z")
            ).not_to intersect_with(
              set_of_range(gt: "2021-05-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            )

            expect(
              set_of_range(gt: "2021-03-12T08:00:00Z", lt: "2021-05-12T08:00:00Z")
            ).not_to intersect_with(
              set_of_range(gte: "2021-05-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            )

            expect(
              set_of_range(gt: "2021-03-12T08:00:00Z", lte: "2021-05-12T08:00:00Z")
            ).to intersect_with(
              set_of_range(gte: "2021-05-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            )
          end
        end

        context "when one set has a double-bounded range and one set has a single bounded range" do
          it "returns true if the double bounded range comes before a less than range" do
            expect(
              set_of_range(gt: "2021-05-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            ).to intersect_with(
              set_of_range(lt: "2021-07-12T08:00:00Z")
            )
          end

          it "returns true if the double bounded range comes after a greater than range" do
            expect(
              set_of_range(gt: "2021-05-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            ).to intersect_with(
              set_of_range(gt: "2021-03-12T08:00:00Z")
            )
          end

          it "returns false if the double bounded range comes after a less than range" do
            expect(
              set_of_range(gt: "2021-05-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            ).not_to intersect_with(
              set_of_range(lt: "2021-04-12T08:00:00Z")
            )
          end

          it "returns false if the double bounded range comes before a greater than range" do
            expect(
              set_of_range(gt: "2021-05-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            ).not_to intersect_with(
              set_of_range(gt: "2021-07-12T08:00:00Z")
            )
          end

          it "returns true if the boundary of the single-bounded range is within the double-bounded range" do
            expect(
              set_of_range(gt: "2021-04-12T08:00:00Z", lt: "2021-06-12T08:00:00Z")
            ).to intersect_with(
              set_of_range(gt: "2021-05-12T08:00:00Z")
            ).and intersect_with(
              set_of_range(lt: "2021-05-12T08:00:00Z")
            )
          end

          it "returns the correct value if they share a boundary" do
            expect(
              set_of_range(gt: "2021-03-12T08:00:00Z", lt: "2021-05-12T08:00:00Z")
            ).not_to intersect_with(
              set_of_range(gt: "2021-05-12T08:00:00Z")
            )

            expect(
              set_of_range(gt: "2021-03-12T08:00:00Z", lte: "2021-05-12T08:00:00Z")
            ).not_to intersect_with(
              set_of_range(gt: "2021-05-12T08:00:00Z")
            )

            expect(
              set_of_range(gt: "2021-03-12T08:00:00Z", lt: "2021-05-12T08:00:00Z")
            ).not_to intersect_with(
              set_of_range(gte: "2021-05-12T08:00:00Z")
            )

            expect(
              set_of_range(gt: "2021-03-12T08:00:00Z", lte: "2021-05-12T08:00:00Z")
            ).to intersect_with(
              set_of_range(gte: "2021-05-12T08:00:00Z")
            )
          end

          context "when one set has a single time value" do
            it "returns true when the time value is within the range of the other set" do
              expect(
                set_of_times("2021-03-12T08:00:00Z")
              ).to intersect_with(
                set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-04-01T00:00:00Z")
              ).and intersect_with(
                set_of_range(gte: "2021-03-12T08:00:00Z", lt: "2021-04-01T00:00:00Z")
              ).and intersect_with(
                set_of_range(gte: "2021-03-01T00:00:00Z", lte: "2021-03-12T08:00:00Z")
              )
            end

            it "returns true when the time value is on the inclusive side of an open range" do
              expect(
                set_of_times("2021-03-12T08:00:00Z")
              ).to intersect_with(
                set_of_range(gte: "2021-03-01T00:00:00Z")
              ).and intersect_with(
                set_of_range(lt: "2021-04-01T00:00:00Z")
              )
            end

            it "returns false when given an empty set" do
              expect(
                set_of_times("2021-03-12T08:00:00Z")
              ).not_to intersect_with(TimeSet::EMPTY)
            end

            it "returns false when the time falls outside the range of the other set" do
              time_set = set_of_times("2021-03-12T08:00:00Z")

              expect(time_set).not_to intersect_with(set_of_range(gte: "2021-03-13T00:00:00Z", lt: "2021-04-01T00:00:00Z"))
              expect(time_set).not_to intersect_with(set_of_range(gte: "2021-02-13T00:00:00Z", lt: "2021-03-11T00:00:00Z"))
              expect(time_set).not_to intersect_with(set_of_range(gte: "2021-03-13T00:00:00Z"))
              expect(time_set).not_to intersect_with(set_of_range(lt: "2021-03-12T08:00:00Z"))
            end
          end

          context "when one set has multiple time values" do
            it "returns true when all the time values fall within the range of the other set" do
              expect(
                set_of_times("2021-03-12T08:00:00Z", "2021-03-13T08:00:00Z", "2021-03-14T08:00:00Z")
              ).to intersect_with(
                set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-04-01T00:00:00Z")
              ).and intersect_with(
                set_of_range(gte: "2021-03-12T08:00:00Z", lt: "2021-04-01T00:00:00Z")
              ).and intersect_with(
                set_of_range(gte: "2021-03-01T00:00:00Z", lte: "2021-03-14T08:00:00Z")
              )
            end

            it "returns true when only one of the time values falls within the range of the other set" do
              expect(
                set_of_times("2021-03-12T08:00:00Z", "2020-03-13T08:00:00Z", "2022-03-14T08:00:00Z")
              ).to intersect_with(
                set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-04-01T00:00:00Z")
              ).and intersect_with(
                set_of_range(gte: "2021-03-12T08:00:00Z", lt: "2021-04-01T00:00:00Z")
              ).and intersect_with(
                set_of_range(gte: "2021-03-01T00:00:00Z", lte: "2021-03-14T08:00:00Z")
              )
            end

            it "returns false when none of the time values falls within the range of the other set" do
              time_set = set_of_times("2021-03-12T08:00:00Z", "2020-03-13T08:00:00Z", "2022-03-14T08:00:00Z")

              expect(time_set).not_to intersect_with(set_of_range(gte: "2023-03-13T00:00:00Z", lt: "2023-04-01T00:00:00Z"))
              expect(time_set).not_to intersect_with(set_of_range(gte: "2020-02-13T00:00:00Z", lt: "2020-03-11T00:00:00Z"))
              expect(time_set).not_to intersect_with(set_of_range(gte: "2023-03-13T00:00:00Z"))
              expect(time_set).not_to intersect_with(set_of_range(lt: "2020-03-12T08:00:00Z"))
            end
          end
        end

        matcher :intersect_with do |range1|
          match do |range2|
            range1.intersect?(range2) && range2.intersect?(range1)
          end

          match_when_negated do |range2|
            !range1.intersect?(range2) && !range2.intersect?(range1)
          end
        end
      end

      describe "#-" do
        context "when diffing time stamps" do
          it "returns the correct set difference" do
            s1 = set_of_times("2021-03-12T08:00:00Z", "2020-03-13T08:00:00Z", "2022-03-14T08:00:00Z")
            s2 = set_of_times("2021-03-12T08:00:00Z")

            expect(s1 - s2).to eq(set_of_times("2020-03-13T08:00:00Z", "2022-03-14T08:00:00Z"))
            expect(s2 - s1).to eq(TimeSet::EMPTY)
          end

          it "ignores a time not present in the original set" do
            s1 = set_of_times("2021-03-12T08:00:00Z", "2020-03-13T08:00:00Z", "2022-03-14T08:00:00Z")
            s2 = set_of_times("2021-04-13T10:00:00Z")

            expect(s1 - s2).to eq(s1)
            expect(s2 - s1).to eq(s2)
          end

          it "returns the correct difference when one set is empty" do
            s1 = set_of_times("2021-03-12T08:00:00Z", "2020-03-13T08:00:00Z", "2022-03-14T08:00:00Z")
            s2 = TimeSet::EMPTY

            expect(s1 - s2).to eq(s1)
            expect(s2 - s1).to eq(TimeSet::EMPTY)
          end

          it "returns an empty `TimeSet` when both times sets contain the same times" do
            s1 = set_of_times("2021-03-12T08:00:00Z", "2020-03-13T08:00:00Z", "2022-03-14T08:00:00Z")
            s2 = set_of_times("2021-03-12T08:00:00Z", "2020-03-13T08:00:00Z", "2022-03-14T08:00:00Z")

            expect(s1 - s2).to eq(TimeSet::EMPTY)
            expect(s2 - s1).to eq(TimeSet::EMPTY)
          end

          it "correctly splits ALL to exclude the subtracted time" do
            t1 = set_of_times("2021-03-12T00:00:00Z")

            expected_difference = set_of_ranges(
              {lt: "2021-03-12T00:00:00Z"},
              {gt: "2021-03-12T00:00:00Z"}
            )

            expect(TimeSet::ALL - t1).to eq(expected_difference)
          end
        end

        context "when diffing sets of ranges with a single intersection" do
          it "correctly splits ALL to exclude the subtracted TimeSet" do
            march_and_april = set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-05-01T00:00:00Z")

            expected_difference = set_of_ranges(
              {lt: "2021-03-01T00:00:00Z"},
              {gte: "2021-05-01T00:00:00Z"}
            )

            expect(TimeSet::ALL - march_and_april).to eq(expected_difference)
          end

          it "correctly truncates the ranges when the ranges overlap" do
            march_and_april = set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-05-01T00:00:00Z")
            april_and_may = set_of_range(gte: "2021-04-01T00:00:00Z", lt: "2021-06-01T00:00:00Z")

            expect(march_and_april - april_and_may).to eq(set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-04-01T00:00:00Z"))
            expect(april_and_may - march_and_april).to eq(set_of_range(gte: "2021-05-01T00:00:00Z", lt: "2021-06-01T00:00:00Z"))
          end

          it "correctly truncates the ranges when the ranges have the same lower bound" do
            march_and_april = set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-05-01T00:00:00Z")
            march = set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-04-01T00:00:00Z")

            expect(march_and_april - march).to eq(set_of_range(gte: "2021-04-01T00:00:00Z", lt: "2021-05-01T00:00:00Z"))
          end

          it "correctly truncates the ranges when the ranges have the same upper bound" do
            march_and_april = set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-05-01T00:00:00Z")
            april = set_of_range(gte: "2021-04-01T00:00:00Z", lt: "2021-05-01T00:00:00Z")

            expect(march_and_april - april).to eq(set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-04-01T00:00:00Z"))
          end

          it "returns the original set of ranges when the ranges do not overlap" do
            march = set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-04-01T00:00:00Z")
            may = set_of_range(gte: "2021-05-01T00:00:00Z", lt: "2021-06-01T00:00:00Z")

            expect(march - may).to eq(march)
            expect(may - march).to eq(may)
          end

          it "returns the original set of ranges when boundless ranges do not overlap" do
            before_march = set_of_range(lt: "2021-03-01T00:00:00Z")
            after_april = set_of_range(gte: "2021-04-01T00:00:00Z")

            expect(before_march - after_april).to eq(before_march)
            expect(after_april - before_march).to eq(after_april)
          end

          it "returns the empty set when fully covered by the subtracted set" do
            april = set_of_range(gte: "2021-04-01T00:00:00Z", lt: "2021-05-01T00:00:00Z")
            march_through_may = set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-06-01T00:00:00Z")
            all1 = TimeSet::ALL
            all2 = TimeSet::ALL

            expect(april - march_through_may).to eq(TimeSet::EMPTY)
            expect(april - TimeSet::ALL).to eq(TimeSet::EMPTY)
            expect(all1 - all2).to eq(TimeSet::EMPTY)
          end

          it "correctly splits the TimeSet when one range is in the middle of the other" do
            march_through_may = set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-06-01T00:00:00Z")
            april = set_of_range(gte: "2021-04-01T00:00:00Z", lt: "2021-05-01T00:00:00Z")

            march_and_may = set_of_ranges(
              {gte: "2021-03-01T00:00:00Z", lt: "2021-04-01T00:00:00Z"},
              {gte: "2021-05-01T00:00:00Z", lt: "2021-06-01T00:00:00Z"}
            )

            expect(march_through_may - april).to eq(march_and_may)
          end

          it "correctly truncates ALL when the subtracted TimeSet is boundless" do
            after_march = set_of_range(gte: "2021-03-01T00:00:00Z")
            before_september = set_of_range(lt: "2021-09-01T00:00:00Z")

            expect(TimeSet::ALL - after_march).to eq(set_of_range(lt: "2021-03-01T00:00:00Z"))
            expect(TimeSet::ALL - before_september).to eq(set_of_range(gte: "2021-09-01T00:00:00Z"))
          end

          it "truncates a beginless range by increasing the lower bound to the upper bound of the subtracted range" do
            before_september = set_of_range(lt: "2021-09-01T00:00:00Z")
            before_march = set_of_range(lt: "2021-03-01T00:00:00Z")

            expect(before_september - before_march).to eq(set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-09-01T00:00:00Z"))
            expect(before_march - before_september).to eq(TimeSet::EMPTY)
          end

          it "truncates an endless range by decreasing the upper bound to the lower bound of the subtracted range" do
            after_march = set_of_range(gte: "2021-03-01T00:00:00Z")
            after_september = set_of_range(gte: "2021-09-01T00:00:00Z")

            expect(after_march - after_september).to eq(set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-09-01T00:00:00Z"))
            expect(after_september - after_march).to eq(TimeSet::EMPTY)
          end

          it "truncates an overlapping beginless range and an endless range by using the bound from the subtracted range" do
            after_march = set_of_range(gte: "2021-03-01T00:00:00Z")
            before_september = set_of_range(lt: "2021-09-01T00:00:00Z")

            expect(after_march - before_september).to eq(set_of_range(gte: "2021-09-01T00:00:00Z"))
            expect(before_september - after_march).to eq(set_of_range(lt: "2021-03-01T00:00:00Z"))
          end

          it "returns an exclusive boundless range when two ranges have the same boundary with only that single time value as the overlap" do
            before_april = set_of_range(lte: "2021-04-01T00:00:00Z")
            after_april = set_of_range(gte: "2021-04-01T00:00:00Z")

            expect(before_april - after_april).to eq(set_of_range(lt: "2021-04-01T00:00:00Z"))
            expect(after_april - before_april).to eq(set_of_range(gt: "2021-04-01T00:00:00Z"))
          end
        end

        context "when diffing set of ranges that have multiple intersections" do
          it "correctly splits the ranges when one TimeSet is a subset of the other" do
            march_through_sept = set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-10-01T00:00:00Z")
            april_and_july = set_of_ranges(
              {gte: "2021-04-01T00:00:00Z", lt: "2021-05-01T00:00:00Z"},
              {gte: "2021-07-01T00:00:00Z", lt: "2021-08-01T00:00:00Z"}
            )

            before_march = {lt: "2021-04-01T00:00:00Z"}
            march = {gte: "2021-03-01T00:00:00Z", lt: "2021-04-01T00:00:00Z"}
            may_through_june = {gte: "2021-05-01T00:00:00Z", lt: "2021-07-01T00:00:00Z"}
            aug_through_sept = {gte: "2021-08-01T00:00:00Z", lt: "2021-10-01T00:00:00Z"}
            after_august = {gte: "2021-08-01T00:00:00Z"}

            expected_difference1 = set_of_ranges(
              march,
              may_through_june,
              aug_through_sept
            )

            expected_difference2 = set_of_ranges(
              before_march,
              may_through_june,
              after_august
            )

            expect(march_through_sept - april_and_july).to eq(expected_difference1)
            expect(TimeSet::ALL - april_and_july).to eq(expected_difference2)
          end

          it "correctly truncates ALL when the subtracted TimeSet has multiple boundless ranges" do
            before_april_after_june = set_of_ranges(
              {lt: "2021-04-01T00:00:00Z"},
              {gte: "2021-06-01T00:00:00Z"}
            )

            march_through_may = set_of_range(gte: "2021-04-01T00:00:00Z", lt: "2021-06-01T00:00:00Z")

            expect(TimeSet::ALL - before_april_after_june).to eq(march_through_may)
          end

          it "correctly truncates the ranges when one TimeSet covers the lower and upper bound of the other" do
            march_through_july = set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-08-01T00:00:00Z")
            feb_march_and_july_sept = set_of_ranges(
              {gte: "2021-02-01T00:00:00Z", lt: "2021-04-01T00:00:00Z"},
              {gte: "2021-07-01T00:00:00Z", lt: "2021-10-01T00:00:00Z"}
            )

            april_through_june = set_of_ranges(
              {gte: "2021-04-01T00:00:00Z", lt: "2021-07-01T00:00:00Z"}
            )

            expect(march_through_july - feb_march_and_july_sept).to eq(april_through_june)
          end

          it "returns a set of a single time when one TimeSet covers the entire other set excluding a single time" do
            march_through_july = set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-08-01T00:00:00Z")
            exclude_may_1 = set_of_ranges(
              {lt: "2021-05-01T00:00:00Z"},
              {gt: "2021-05-01T00:00:00Z"}
            )

            expect(march_through_july - exclude_may_1).to eq(set_of_times("2021-05-01T00:00:00Z"))
          end

          it "returns an empty TimeSet when one TimeSet covers the other TimeSet" do
            march_through_july = set_of_range(gte: "2021-03-01T00:00:00Z", lt: "2021-08-01T00:00:00Z")
            around_may_1 = set_of_ranges(
              {lte: "2021-05-01T00:00:00Z"},
              {gte: "2021-05-01T00:00:00Z"}
            )

            expect(march_through_july - around_may_1).to eq(TimeSet::EMPTY)
          end

          it "correctly truncates the ranges when one TimeSet is a subset of the other" do
            march_june_and_aug_nov = set_of_ranges(
              {gte: "2021-03-01T00:00:00Z", lt: "2021-07-01T00:00:00Z"},
              {gte: "2021-08-01T00:00:00Z", lt: "2021-12-01T00:00:00Z"}
            )

            april_may_and_sept_oct = set_of_ranges(
              {gte: "2021-04-01T00:00:00Z", lt: "2021-06-01T00:00:00Z"},
              {gte: "2021-09-01T00:00:00Z", lt: "2021-11-01T00:00:00Z"}
            )

            march_june_aug_nov = set_of_ranges(
              {gte: "2021-03-01T00:00:00Z", lt: "2021-04-01T00:00:00Z"},
              {gte: "2021-06-01T00:00:00Z", lt: "2021-07-01T00:00:00Z"},
              {gte: "2021-08-01T00:00:00Z", lt: "2021-09-01T00:00:00Z"},
              {gte: "2021-11-01T00:00:00Z", lt: "2021-12-01T00:00:00Z"}
            )
            expect(march_june_and_aug_nov - april_may_and_sept_oct).to eq(march_june_aug_nov)
          end
        end

        it "returns an empty TimeSet when both sets are empty" do
          empty1 = TimeSet::EMPTY
          empty2 = TimeSet::EMPTY

          expect(empty1 - empty2).to eq(TimeSet::EMPTY)
        end

        it "returns an empty TimeSet when ALL is subtracted from EMPTY" do
          expect(TimeSet::EMPTY - TimeSet::ALL).to eq(TimeSet::EMPTY)
        end

        it "returns ALL when the EMPTY TimeSet is subtracted from the ALL TimeSet" do
          expect(TimeSet::ALL - TimeSet::EMPTY).to eq(TimeSet::ALL)
        end
      end

      describe "#negate" do
        it "returns EMPTY for ALL and vice versa" do
          expect(TimeSet::ALL.negate).to be(TimeSet::EMPTY)
          expect(TimeSet::EMPTY.negate).to be(TimeSet::ALL)
        end

        it "returns the set containing all times that were excluded from the original set" do
          march_to_june_and_aug_to_nov = set_of_ranges(
            {gte: "2021-03-01T00:00:00Z", lt: "2021-07-01T00:00:00Z"},
            {gte: "2021-08-01T00:00:00Z", lt: "2021-12-01T00:00:00Z"}
          )

          before_march_and_july_and_after_nov = set_of_ranges(
            {lt: "2021-03-01T00:00:00Z"},
            {gte: "2021-07-01T00:00:00Z", lt: "2021-08-01T00:00:00Z"},
            {gte: "2021-12-01T00:00:00Z"}
          )

          expect(march_to_june_and_aug_to_nov.negate).to eq before_march_and_july_and_after_nov
          expect(before_march_and_july_and_after_nov.negate).to eq march_to_june_and_aug_to_nov
        end
      end

      def set_of_range(expected_empty: false, **options)
        options = options.transform_values { |iso8601_string| ::Time.iso8601(iso8601_string) }

        TimeSet.of_range(**options).tap do |time_set|
          expect(time_set.empty?).to eq(expected_empty)
        end
      end

      def set_of_ranges(*options_for_ranges)
        ranges = options_for_ranges.map { |opts| set_of_range(**opts) }.map do |time_set|
          expect(time_set.ranges.size).to eq(1)
          time_set.ranges.first
        end

        TimeSet.of_range_objects(ranges)
      end

      def set_of_times(*iso8601_strings)
        times = iso8601_strings.map { |s| ::Time.iso8601(s) }

        TimeSet.of_times(times).tap do |time_set|
          expect(time_set.empty?).to eq(iso8601_strings.empty?)
        end
      end
    end
  end
end
