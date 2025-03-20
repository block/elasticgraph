# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Support
    # @private
    module TimeUtil
      NANOS_PER_SECOND = 1_000_000_000
      NANOS_PER_MINUTE = NANOS_PER_SECOND * 60
      NANOS_PER_HOUR = NANOS_PER_MINUTE * 60

      # Simple helper function to convert a local time string (such as `03:45:12` or `12:30:43.756`)
      # to an integer value between 0 and 24 * 60 * 60 * 1,000,000,000 - 1 representing the nano of day
      # for the local time value.
      #
      # This is meant to match the behavior of Java's `LocalTime#toNanoOfDay()` API:
      # https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/time/LocalTime.html#toNanoOfDay()
      #
      # This is specifically useful when we need to work with local time values in a script: by converting
      # a local time parameter to nano-of-day, our script can more efficiently compare values, avoiding the
      # need to parse the same local time parameters over and over again as it applies the script to each
      # document.
      #
      # Note: this method assumes the given `local_time_string` is well-formed. You'll get an exception if
      # you provide a malformed value, but no effort has been put into giving a clear error message. The
      # caller is expected to have already validated that the `local_time_string` is formatted correctly.
      def self.nano_of_day_from_local_time(local_time_string)
        hours_str, minutes_str, full_seconds_str = local_time_string.split(":")
        seconds_str, subseconds_str = (_ = full_seconds_str).split(".")

        hours = Integer(_ = hours_str, 10)
        minutes = Integer(_ = minutes_str, 10)
        seconds = Integer(seconds_str, 10)
        nanos = Integer(subseconds_str.to_s.ljust(9, "0"), 10)

        (hours * NANOS_PER_HOUR) + (minutes * NANOS_PER_MINUTE) + (seconds * NANOS_PER_SECOND) + nanos
      end

      # Helper method for advancing time. Unfortunately, Ruby's core `Time` type does not directly support this.
      # ActiveSupport (from rails) provides this functionality, but we don't depend on rails at all and don't
      # want to add such a heavyweight dependency for such a small thing.
      #
      # Luckily, our needs are quite limited, which makes this a much simpler problem then a general purpose `time.advance(...)` API:
      #
      # - We only need to support year, month, day, and hour advances.
      # - We only ever need to advance a single unit.
      #
      # This provides a simple, correct implementation for that constrained problem space.
      def self.advance_one_unit(time, unit)
        case unit
        when :year
          with_updated(time, year: time.year + 1)
        when :month
          maybe_next_month =
            if time.month == 12
              with_updated(time, year: time.year + 1, month: 1)
            else
              with_updated(time, month: time.month + 1)
            end

          # If the next month has fewer days than the month of `time`, then it can "spill over" to a day
          # from the first week of the month following that. For example, if the date of `time` was 2021-01-31
          # and we add a month, it attempts to go to `2021-02-31` but such a date doesn't exist--instead
          # `maybe_next_month` will be on `2021-03-03` because of the overflow. Here we correct for that.
          #
          # Our assumption (which we believe to be correct) is that every time this happens, both of these are true:
          # - `time.day` is near the end of its month
          # - `maybe_next_month.day` is near the start of its month
          #
          # ...and furthermore, we do not believe there is any other case where `time.day` and `maybe_next_month.day` can differ.
          if time.day > maybe_next_month.day
            corrected_date = maybe_next_month.to_date - maybe_next_month.day
            with_updated(time, year: corrected_date.year, month: corrected_date.month, day: corrected_date.day)
          else
            maybe_next_month
          end
        when :day
          next_day = time.to_date + 1
          with_updated(time, year: next_day.year, month: next_day.month, day: next_day.day)
        when :hour
          time + 3600
        end
      end

      private_class_method def self.with_updated(time, year: time.year, month: time.month, day: time.day)
        # UTC needs to be treated special here due to an oddity of Ruby's Time class:
        #
        # > Time.utc(2021, 12, 2, 12, 30, 30).iso8601
        #  => "2021-12-02T12:30:30Z"
        # > Time.new(2021, 12, 2, 12, 30, 30, 0).iso8601
        #  => "2021-12-02T12:30:30+00:00"
        #
        # We want to preserve the `Z` suffix on the ISO8601 representation of the advanced time
        # (if it was there on the original time), so we use the `::Time.utc` method here to do that.
        # Non-UTC time must use `::Time.new(...)` with a UTC offset, though.
        if time.utc?
          ::Time.utc(year, month, day, time.hour, time.min, time.sec.to_r + time.subsec)
        else
          ::Time.new(year, month, day, time.hour, time.min, time.sec.to_r + time.subsec, time.utc_offset)
        end
      end
    end
  end
end
