# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "support/scalar_coercion_adapter"

module ElasticGraph
  class GraphQL
    module ScalarCoercionAdapters
      RSpec.describe "DateTime" do
        include_context "scalar coercion adapter support", "DateTime"

        let(:other_format_string) do
          ::Time.iso8601("2021-11-05T12:30:00Z").to_s.tap do |string|
            ::Time.parse(string) # prove it is parseable
            expect { ::Time.iso8601(string) }.to raise_error(ArgumentError)
          end
        end

        context "input coercion" do
          it "accepts an ISO8601 formatted timestamp string with ms precision" do
            expect_input_value_to_be_accepted("2021-11-05T12:30:00.123Z")
          end

          it "accepts an ISO8601 formatted timestamp string with s precision" do
            string_time = "2021-11-05T12:30:05Z"

            expect_input_value_to_be_accepted(string_time, as: string_time.sub("05Z", "05.000Z"))
          end

          it "supports time zones besides UTC" do
            expect_input_value_to_be_accepted("2021-11-05T12:30:00.123-07:00")
          end

          it "accepts a `nil` value as-is" do
            expect_input_value_to_be_accepted(nil)
          end

          it "rejects other time formats" do
            expect_input_value_to_be_rejected(other_format_string, "ISO8601")
          end

          it "rejects an ISO8601-formatted Date" do
            expect_input_value_to_be_rejected("2021-11-05", "ISO8601")
          end

          it "rejects a string that is not a timestamp string" do
            expect_input_value_to_be_rejected("not a timestamp")
          end

          it "rejects an ISO8601 formatted timestamp with more than 4 digits for the year because the datastore strict format we use requires 4 digits" do
            expect_input_value_to_be_rejected("20021-11-05T12:30:00Z")
            expect_input_value_to_be_rejected("200021-11-05T12:30:00Z")
          end

          it "allows timestamps before the year 1000" do
            expect_input_value_to_be_accepted("0001-01-01T00:00:00.000Z")
          end

          it "rejects numbers" do
            expect_input_value_to_be_rejected(1231232131)
            expect_input_value_to_be_rejected(34.5)
          end

          it "rejects booleans" do
            expect_input_value_to_be_rejected(true)
            expect_input_value_to_be_rejected(false)
          end

          it "rejects a list of ISO8601 timestamp strings" do
            expect_input_value_to_be_rejected([::Time.now.iso8601])
          end
        end

        context "result coercion" do
          it "returns a Time result in ISO8601 format" do
            string, time = string_time_pair_from("2021-11-05T12:30:00.123Z")

            expect_result_to_be_returned(time, as: string)
          end

          it "formats a Time result with ms precision even if the time value only really has second precision" do
            string, time = string_time_pair_from("2021-11-05T12:30:00Z")

            expect_result_to_be_returned(time, as: string.sub("00Z", "00.000Z"))
          end

          it "returns a string already formatted in ISO8061 format as-is" do
            string, _time = string_time_pair_from("2021-11-05T12:30:00.123Z")

            expect_result_to_be_returned(string, as: string)
          end

          it "reformats a second-precision ISO8601 string to be ms-precision" do
            string, _time = string_time_pair_from("2021-11-05T12:30:00Z")

            expect_result_to_be_returned(string, as: string.sub("00Z", "00.000Z"))
          end

          it "supports time zones besides UTC" do
            string, time = string_time_pair_from("2021-11-05T12:30:00.123-07:00")

            expect_result_to_be_returned(time, as: string)
          end

          it "returns `nil` as is" do
            expect_result_to_be_returned(nil)
          end

          it "returns `nil` in place of a number" do
            expect_result_to_be_replaced_with_nil(1231232131)
            expect_result_to_be_replaced_with_nil(34.5)
          end

          it "returns `nil` in place of a boolean" do
            expect_result_to_be_replaced_with_nil(false)
            expect_result_to_be_replaced_with_nil(true)
          end

          it "returns `nil` in place of a Date" do
            expect_result_to_be_replaced_with_nil(::Date.new(2021, 5, 12))
          end

          it "returns `nil` in place of a String that is not in ISO8601 format" do
            expect_result_to_be_replaced_with_nil(other_format_string)
          end

          it "returns `nil` in place of a String that is not a timestamp string" do
            expect_result_to_be_replaced_with_nil("not a timestamp")
          end

          it "returns `nil` in place of a list of valid timestamp values" do
            expect_result_to_be_replaced_with_nil([::Time.now.iso8601])
            expect_result_to_be_replaced_with_nil([::Time.now])
          end
        end

        def string_time_pair_from(iso8601_string)
          [iso8601_string, ::Time.iso8601(iso8601_string)]
        end
      end
    end
  end
end
