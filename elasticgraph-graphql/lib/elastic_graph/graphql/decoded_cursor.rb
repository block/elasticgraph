# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "base64"
require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/support/memoizable_data"
require "json"

module ElasticGraph
  class GraphQL
    # Provides the in-memory representation of a cursor after it has been decoded, as a simple hash of sort values.
    #
    # The datastore's `search_after` pagination uses an array of values (which represent values of the fields you are
    # sorting by). A cursor returned when we applied one sort is generally not valid when we apply a completely
    # different sort. To ensure we can detect this, the encoder encodes a hash of sort fields and values, ensuring
    # each value in the cursor is properly labeled with what field it came from. This allows us
    # to detect situations where the client uses a cursor with a completely different sort applied, while
    # allowing some minor variation in the sort. The following are still allowed:
    #
    #   - Changing the direction of the sort (from `asc` to `desc` or vice-versa)
    #   - Re-ordering the sort (e.g. changing from `[amount_money_DESC, created_at_ASC]`
    #     to `[created_at_ASC, amount_money_DESC]`
    #   - Removing fields from the sort (e.g. changing from `[amount_money_DESC, created_at_ASC]`
    #     to `[amount_money_DESC]`) -- but adding fields is not allowed
    #
    # While we don't necessarily recommend clients change these things between pagination requests (the
    # behavior may be surprising to the user), there is no ambiguity in how to support them, and we do not
    # feel like it makes sense to restrict it at this point.
    class DecodedCursor < Support::MemoizableData.define(:sort_values)
      # Methods provided by `MemoizableData.define`:
      # @dynamic initialize, sort_values

      # Tries to decode the given string cursor, returning `nil` if it is invalid.
      def self.try_decode(string)
        decode!(string)
      rescue Errors::InvalidCursorError
        nil
      end

      # Tries to decode the given string cursor, raising an `Errors::InvalidCursorError` if it's invalid.
      def self.decode!(string)
        return SINGLETON if string == SINGLETON_CURSOR
        json = ::Base64.urlsafe_decode64(string)
        new(::JSON.parse(json))
      rescue ::ArgumentError, ::JSON::ParserError
        raise Errors::InvalidCursorError, "`#{string}` is an invalid cursor."
      end

      # Encodes the cursor to a string using JSON and Base64 encoding.
      def encode
        @encode ||= begin
          json = ::JSON.fast_generate(sort_values)
          ::Base64.urlsafe_encode64(json, padding: false)
        end
      end

      # A special cursor instance for when we need a cursor but have only a static collection of a single
      # element without any sort of key we can encode.
      SINGLETON = new({}).tap do |sc|
        # Ensure the special string value is returned even though our `sort_values` are empty.
        def sc.encode
          SINGLETON_CURSOR
        end
      end

      # Used to build decoded cursor values for the given `sort_fields`.
      class Factory < Data.define(:sort_fields)
        # Methods provided by `Data.define`:
        # @dynamic initialize, sort_fields

        # Builds a factory from a list like:
        # `[{ 'amount_money.amount' => 'asc' }, { 'created_at' => 'desc' }]`.
        def self.from_sort_list(sort_list)
          sort_fields = sort_list.map do |hash|
            if hash.values.any? { |v| !v.is_a?(::Hash) } || hash.values.flat_map(&:keys) != ["order"]
              raise Errors::InvalidSortFieldsError,
                "Given `sort_list` contained an invalid entry. Each must be a flat hash with one entry. Got: #{sort_list.inspect}"
            end

            # Steep thinks it could be `nil` because `hash.keys` could be empty, but we raise an error above in
            # that case, so we know this will wind up being a `String`. `_` here silences Steep's type check error.
            _ = hash.keys.first
          end

          if sort_fields.uniq.size < sort_fields.size
            raise Errors::InvalidSortFieldsError,
              "Given `sort_list` contains a duplicate field, which the CursorEncoder cannot handler. " \
              "The caller is responsible for de-duplicating the sort list fist. Got: #{sort_list.inspect}"
          end

          new(sort_fields)
        end

        def build(sort_values)
          unless sort_values.size == sort_fields.size
            raise Errors::CursorEncodingError,
              "size of sort values (#{sort_values.inspect}) does not match the " \
              "size of sort fields (#{sort_fields.inspect})"
          end

          DecodedCursor.new(sort_fields.zip(sort_values).to_h)
        end

        alias_method :to_s, :inspect

        module Null
          def self.build(sort_values)
            DecodedCursor.new(sort_values.map(&:to_s).zip(sort_values).to_h)
          end
        end
      end
    end
  end
end
