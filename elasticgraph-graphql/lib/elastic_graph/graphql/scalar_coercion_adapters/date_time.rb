# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "time"

module ElasticGraph
  class GraphQL
    module ScalarCoercionAdapters
      class DateTime
        PRECISION = 3 # millisecond precision

        def self.coerce_input(value, ctx)
          return value if value.nil?

          time = ::Time.iso8601(value)

          # Verify we do not have more than 4 digits for the year. The datastore `strict_date_time` format we use only supports 4 digit years:
          #
          # > Most of the below formats have a `strict` companion format, which means that year, month and day parts of the
          # > week must use respectively 4, 2 and 2 digits exactly, potentially prepending zeros.
          #
          # https://www.elastic.co/guide/en/elasticsearch/reference/8.12/mapping-date-format.html#built-in-date-formats
          raise_coercion_error(value) if time.year > 9999

          # We ultimately wind up passing input args to the datastore as our GraphQL engine receives
          # them (it doesn't do any formatting of DateTime args to what the datastore needs) so we do
          # that here instead. We have configured the datastore to expect DateTimes in `strict_date_time`
          # format, so here we convert it to that format (which is just ISO8601 format). Ultimately,
          # that means that this method just "roundtrips" the input string back to a string, but it validates
          # the string is formatted correctly and returns a string in the exact format we need for the datastore.
          time.iso8601(PRECISION)
        rescue ::ArgumentError, ::TypeError
          raise_coercion_error(value)
        end

        def self.coerce_result(value, ctx)
          case value
          when ::Time
            value.iso8601(PRECISION)
          when ::String
            ::Time.iso8601(value).iso8601(PRECISION)
          end
        rescue ::ArgumentError
          nil
        end

        private_class_method def self.raise_coercion_error(value)
          raise ::GraphQL::CoercionError,
            "Could not coerce value #{value.inspect} to DateTime: must be formatted as an ISO8601 " \
            "DateTime string with a 4 digit year (example: #{::Time.now.getutc.iso8601.inspect})."
        end
      end
    end
  end
end
