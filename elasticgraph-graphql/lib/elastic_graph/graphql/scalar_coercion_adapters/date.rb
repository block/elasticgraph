# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module ScalarCoercionAdapters
      class Date
        def self.coerce_input(value, ctx)
          return value if value.nil?

          # `::Date.iso8601` will happily parse a time ISO8601 string like `2021-11-10T12:30:00Z`
          # but for simplicity we only want to support a Date string (like `2021-11-10`),
          # so we detect that case here.
          raise ::ArgumentError if value.is_a?(::String) && value.include?(":")

          date = ::Date.iso8601(value)

          # Verify we have a 4 digit year. The datastore `strict_date_time` format se use only supports 4 digit years:
          #
          # > Most of the below formats have a `strict` companion format, which means that year, month and day parts of the
          # > week must use respectively 4, 2 and 2 digits exactly, potentially prepending zeros.
          #
          # https://www.elastic.co/guide/en/elasticsearch/reference/7.10/mapping-date-format.html#built-in-date-formats
          raise_coercion_error(value) if date.year < 1000 || date.year > 9999

          # We ultimately wind up passing input args to the datastore as our GraphQL engine receives
          # them (it doesn't do any formatting of Date args to what the datastore needs) so we do
          # that here instead. We have configured the datastore to expect Dates in `strict_date`
          # format, so here we convert it to that format (which is just ISO8601 format). Ultimately,
          # that means that this method just "roundtrips" the input string back to a string, but it
          # validates the string is formatted correctly and returns a string in the exact format we
          # need for the datastore. Also, we technically don't have to do this; ISO8601 format is
          # the format that `Date` objects are serialized as in JSON, anyway. But we _have_ to do this
          # for `DateTime` objects so we also do it here for parity/consistency.
          date.iso8601
        rescue ArgumentError, ::TypeError
          raise_coercion_error(value)
        end

        def self.coerce_result(value, ctx)
          case value
          when ::Date
            value.iso8601
          when ::String
            ::Date.iso8601(value).iso8601
          end
        rescue ::ArgumentError
          nil
        end

        private_class_method def self.raise_coercion_error(value)
          raise ::GraphQL::CoercionError,
            "Could not coerce value #{value.inspect} to Date: must be formatted " \
            "as an ISO8601 Date string (example: #{::Date.today.iso8601.inspect})."
        end
      end
    end
  end
end
