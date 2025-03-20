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
      RSpec.describe "Date" do
        include_context "scalar coercion adapter support", "Date"

        let(:other_format_string) do
          "2021/03/27".tap do |string|
            ::Date.parse(string) # prove it is parseable
            expect { ::Date.iso8601(string) }.to raise_error(ArgumentError)
          end
        end

        context "input coercion" do
          it "accepts an ISO8601 formatted date string with ms precision" do
            expect_input_value_to_be_accepted("2021-11-05")
          end

          it "rejects a year that is more than 4 digits because the datastore strict format we use requires 4 digits" do
            expect_input_value_to_be_rejected("20021-11-05")
            expect_input_value_to_be_rejected("200021-11-05")
          end

          it "accepts a `nil` value as-is" do
            expect_input_value_to_be_accepted(nil)
          end

          it "rejects other date formats" do
            expect_input_value_to_be_rejected(other_format_string, "ISO8601")
          end

          it "rejects an ISO8601-formatted DateTime" do
            expect_input_value_to_be_rejected("2021-11-05T12:30:00Z", "ISO8601")
          end

          it "rejects a string that is not a date string" do
            expect_input_value_to_be_rejected("not a date")
          end

          it "rejects numbers" do
            expect_input_value_to_be_rejected(1231232131)
            expect_input_value_to_be_rejected(34.5)
          end

          it "rejects booleans" do
            expect_input_value_to_be_rejected(true)
            expect_input_value_to_be_rejected(false)
          end

          it "rejects a list of ISO8601 date strings" do
            expect_input_value_to_be_rejected([::Date.today.iso8601])
          end
        end

        context "result coercion" do
          it "returns a Date result in ISO8601 format" do
            string, date = string_date_pair_from("2021-11-05")

            expect_result_to_be_returned(date, as: string)
          end

          it "returns a string already formatted in ISO8061 format as-is" do
            string, _date = string_date_pair_from("2021-11-05")

            expect_result_to_be_returned(string, as: string)
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

          it "returns `nil` in place of a full timestamp" do
            expect_result_to_be_replaced_with_nil(::Time.new(2021, 5, 12, 12, 30, 30))
          end

          it "returns `nil` in place of a String that is not in ISO8601 format" do
            expect_result_to_be_replaced_with_nil(other_format_string)
          end

          it "returns `nil` in place of a String that is not a date string" do
            expect_result_to_be_replaced_with_nil("not a date")
          end

          it "returns `nil` in place of a list of valid date values" do
            expect_result_to_be_replaced_with_nil([::Date.today.iso8601])
            expect_result_to_be_replaced_with_nil([::Date.today])
          end
        end

        def string_date_pair_from(iso8601_string)
          [iso8601_string, ::Date.iso8601(iso8601_string)]
        end
      end
    end
  end
end
