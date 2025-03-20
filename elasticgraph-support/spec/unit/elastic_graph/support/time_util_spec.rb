# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/time_util"
require "time"

module ElasticGraph
  module Support
    RSpec.describe TimeUtil do
      describe ".nano_of_day_from_local_time" do
        it "converts `00:00:00` to 0" do
          expect_nanos("00:00:00", 0)
        end

        it "converts single digit hours/minutes/seconds" do
          expect_nanos("01:03:02", 3782000000000)
        end

        it "works correctly with single digit values that `Integer(...)` requires a base arg for" do
          # `Integer(...)` treats a leading `0` as indicating an octal (base 8) number.
          # Consequently, `Integer("08")` and `Integer("09")` are not valid unless passing a base arg.
          # It's important `nano_of_day_from_local_time` does this so we cover that case here.
          expect(Integer("07")).to eq(7) # not needed for values under 08 since 0 to 7 are the same in decimal and octal.
          expect { Integer("08") }.to raise_error(a_string_including("invalid value for Integer", "08"))
          expect { Integer("09") }.to raise_error(a_string_including("invalid value for Integer", "09"))
          expect(Integer("08", 10)).to eq(8)
          expect(Integer("09", 10)).to eq(9)

          expect_nanos("08:08:08.08", 29288080000000)
          expect_nanos("09:09:09.09", 32949090000000)
        end

        it "converts double digit hours/minutes/seconds" do
          expect_nanos("14:37:12", 52632000000000)
        end

        it "supports milliseconds" do
          expect_nanos("12:35:14.123", 45314123000000)
          expect_nanos("12:35:14.009", 45314009000000)
        end

        it "allows any number of decimal digits" do
          expect_nanos("02:35:14.1", 9314100000000)
          expect_nanos("02:35:14.10", 9314100000000)
          expect_nanos("02:35:14.100", 9314100000000)
          expect_nanos("02:35:14.1000", 9314100000000)
        end

        it "converts `23:59:59.999`" do
          expect_nanos("23:59:59.999", 86399999000000)
        end

        it "rejects non-numeric characters in the hours position" do
          expect_invalid_value("ab:00:00", "ab")
        end

        it "rejects non-numeric characters in the minutes position" do
          expect_invalid_value("00:cd:00", "cd")
        end

        it "rejects non-numeric characters in the seconds position" do
          expect_invalid_value("00:00:ef", "ef")
        end

        it "rejects non-numeric characters in the sub-seconds position" do
          expect_invalid_value("00:00:00.xyz", "xyz000000")
        end

        def expect_nanos(local_time, expected_nanos)
          converted = TimeUtil.nano_of_day_from_local_time(local_time)
          expect(converted).to eq(expected_nanos)

          # Java has a simple API to convert a local time string to nano-of-day (`LocalTime.parse(str).toNanoOfDay()`)
          # So we can nicely use it as a source of truth to verify that our expected nanos are correct. The
          # `script/local_time_to_nano_of_day.java` script uses that Java API to do the conversion for us.
          # However, it's kinda slow--on my M1 mac it's the difference between these specs taking < 2 ms and
          # them taking 2-3 seconds.
          #
          # We don't usually want these tests to go 1000x slower just to verify that our expected values are in
          # fact correct, but it's nice to run that extra check on CI.
          #
          # If you're ever adding new examples to the above, you may also want to enable this
          # (just change to `if true`).
          if ENV["CI"]
            # :nocov: -- not executed in all environments
            nanos_according_to_java = `java --source 11 #{SPEC_ROOT}/support/local_time_to_nano_of_day.java #{local_time}`.strip
            expect(expected_nanos.to_s).to eq(nanos_according_to_java)
            # :nocov:
          end
        end

        def expect_invalid_value(local_time_str, bad_part)
          expect {
            TimeUtil.nano_of_day_from_local_time(local_time_str)
          }.to raise_error ArgumentError, a_string_including("invalid value", bad_part.inspect)
        end
      end

      describe ".advance_one_unit" do
        shared_examples_for "advancing time" do
          it "can advance a time by one :year" do
            initial = parse_time("2021-12-01 15:20:04.36235")
            next_year = parse_time("2022-12-01 15:20:04.36235")

            expect(TimeUtil.advance_one_unit(initial, :year)).to exactly_equal next_year
          end

          it "can advance a time by one :month (within a year)" do
            initial = parse_time("2021-09-01 15:20:04.36235")
            next_month = parse_time("2021-10-01 15:20:04.36235")

            expect(TimeUtil.advance_one_unit(initial, :month)).to exactly_equal next_month
          end

          it "can advance a time by one :month (across a year boundary)" do
            initial = parse_time("2021-12-01 15:20:04.36235")
            next_month = parse_time("2022-01-01 15:20:04.36235")

            expect(TimeUtil.advance_one_unit(initial, :month)).to exactly_equal next_month
          end

          it "rounds down to the last day of the month when advancing from a day-of-month that doesn't exist on the next month" do
            initial = parse_time("2021-01-31 15:20:04.36235")
            next_month = parse_time("2021-02-28 15:20:04.36235")

            expect(TimeUtil.advance_one_unit(initial, :month)).to exactly_equal next_month
          end

          it "can advance a time by one :day (within a month)" do
            initial = parse_time("2021-12-01 15:20:04.36235")
            next_day = parse_time("2021-12-02 15:20:04.36235")

            expect(TimeUtil.advance_one_unit(initial, :day)).to exactly_equal next_day
          end

          it "can advance a time by one :day (across a month boundary, but within a year)" do
            initial = parse_time("2021-02-28 15:20:04.36235")
            next_day = parse_time("2021-03-01 15:20:04.36235")

            expect(TimeUtil.advance_one_unit(initial, :day)).to exactly_equal next_day
          end

          it "can advance a time by one :day (across a year boundary)" do
            initial = parse_time("2021-12-31 15:20:04.36235")
            next_day = parse_time("2022-01-01 15:20:04.36235")

            expect(TimeUtil.advance_one_unit(initial, :day)).to exactly_equal next_day
          end

          it "can advance a time by one :hour (within a day)" do
            initial = parse_time("2021-12-01 15:20:04.36235")
            next_hour = parse_time("2021-12-01 16:20:04.36235")

            expect(TimeUtil.advance_one_unit(initial, :hour)).to exactly_equal next_hour
          end

          it "can advance a time by one :hour (across a day boundary, but within a month)" do
            initial = parse_time("2021-12-01 23:20:04.36235")
            next_hour = parse_time("2021-12-02 00:20:04.36235")

            expect(TimeUtil.advance_one_unit(initial, :hour)).to exactly_equal next_hour
          end

          it "can advance a time by one :hour (across a month boundary, but within a year)" do
            initial = parse_time("2021-11-30 23:20:04.36235")
            next_hour = parse_time("2021-12-01 00:20:04.36235")

            expect(TimeUtil.advance_one_unit(initial, :hour)).to exactly_equal next_hour
          end

          it "can advance a time by one :hour (across a year boundary)" do
            initial = parse_time("2021-12-31 23:20:04.36235")
            next_hour = parse_time("2022-01-01 00:20:04.36235")

            expect(TimeUtil.advance_one_unit(initial, :hour)).to exactly_equal next_hour
          end

          # Given our `advancementUnit` type, steep complains if we put any logic in
          # `advance_one_unit` to have it raise an error on other types, claiming the
          # code is unreachable. However, our code coverage check fails if we don't
          # cover that case, so we cover it here with a simple test that just shows it
          # returns nil.
          it "returns `nil` when given any other time units" do
            initial = parse_time("2021-12-31 23:20:04.36235")

            expect(TimeUtil.advance_one_unit(initial, :minute)).to be_nil
            expect(TimeUtil.advance_one_unit(initial, :decade)).to be_nil
          end
        end

        context "with a UTC time" do
          include_examples "advancing time" do
            def parse_time(time_string)
              ::Time.parse("#{time_string}Z")
            end
          end
        end

        context "with a non-UTC time" do
          include_examples "advancing time" do
            def parse_time(time_string)
              ::Time.parse("#{time_string} -0800")
            end
          end
        end

        def exactly_equal(time)
          # Here we verify both simple time equality and also that the ISO8601 representations are equal.
          # This is necessary to deal with an oddity of Ruby's Time class:
          #
          # > Time.utc(2021, 12, 2, 12, 30, 30).iso8601
          #  => "2021-12-02T12:30:30Z"
          # > Time.new(2021, 12, 2, 12, 30, 30, 0).iso8601
          #  => "2021-12-02T12:30:30+00:00"
          #
          # We want to preserve the `Z` suffix on the advanced time (if it was there on the original time),
          # so the extra check on the ISO8601 repsentation enforces that.
          eq(time).and have_attributes(iso8601: time.iso8601)
        end
      end
    end
  end
end
