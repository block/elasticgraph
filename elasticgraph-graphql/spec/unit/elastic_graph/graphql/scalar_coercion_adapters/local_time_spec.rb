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
      RSpec.describe "LocalTime" do
        include_context "scalar coercion adapter support", "LocalTime"

        context "input coercion" do
          it "accepts a well-formatted time with hour 00 to 23" do
            0.upto(9) do |hour|
              expect_input_value_to_be_accepted("0#{hour}:00:00")
            end

            10.upto(23) do |hour|
              expect_input_value_to_be_accepted("#{hour}:00:00")
            end
          end

          it "rejects hours greater than 23" do
            24.upto(100) do |hour|
              expect_input_value_to_be_rejected("#{hour}:00:00")
            end
          end

          it "accepts a well-formatted time with minute 00 to 59" do
            0.upto(9) do |minute|
              expect_input_value_to_be_accepted("00:0#{minute}:00")
            end

            10.upto(59) do |minute|
              expect_input_value_to_be_accepted("00:#{minute}:00")
            end
          end

          it "rejects minutes greater than 59" do
            60.upto(100) do |minute|
              expect_input_value_to_be_rejected("00:#{minute}0:00")
            end
          end

          it "accepts a well-formatted time with second 00 to 59" do
            0.upto(9) do |second|
              expect_input_value_to_be_accepted("00:00:0#{second}")
            end

            10.upto(59) do |second|
              expect_input_value_to_be_accepted("00:00:#{second}")
            end
          end

          it "rejects seconds greater than 59" do
            60.upto(100) do |second|
              expect_input_value_to_be_rejected("00:00:#{second}")
            end
          end

          it "rejects single-digit hour, minute, or second" do
            expect_input_value_to_be_rejected("7:00:00")
            expect_input_value_to_be_rejected("00:7:00")
            expect_input_value_to_be_rejected("00:00:7")
          end

          it "accepts up to 3 decimal subsecond digits" do
            expect_input_value_to_be_accepted("00:00:00.1")
            expect_input_value_to_be_accepted("00:00:00.12")
            expect_input_value_to_be_accepted("00:00:00.123")
          end

          it "rejects malformed or too many decimal digits" do
            expect_input_value_to_be_rejected("00:00:00.1a")
            expect_input_value_to_be_rejected("00:00:00.")
            expect_input_value_to_be_rejected("00:00:00.1234")
          end

          it "rejects non-string values" do
            expect_input_value_to_be_rejected(3)
            expect_input_value_to_be_rejected(3.7)
            expect_input_value_to_be_rejected(true)
            expect_input_value_to_be_rejected(false)
            expect_input_value_to_be_rejected(["00:00:00"])
            expect_input_value_to_be_rejected([])
          end

          it "rejects strings that are not formatted like a time at all" do
            expect_input_value_to_be_rejected("not a time")
          end

          it "rejects strings that are not quite formatted correctly" do
            expect_input_value_to_be_rejected("00:00") # no second part
            expect_input_value_to_be_rejected("000000") # no colons
            expect_input_value_to_be_rejected("07:00:00am") # am/pm
            expect_input_value_to_be_rejected("07:00:00AM") # am/pm
            expect_input_value_to_be_rejected("07:00:00 am") # am/pm
            expect_input_value_to_be_rejected("07:00:00 AM") # am/pm
            expect_input_value_to_be_rejected("07:00:00Z") # time zone
            expect_input_value_to_be_rejected("07:00:00+03:00") # time zone offset
          end

          it "rejects strings that use another alphanumeric character in place of the dot (ensuring the dot in the pattern is not treated as a regex wildcard)" do
            expect_input_value_to_be_rejected("00:00:00a123")
            expect_input_value_to_be_rejected("00:00:003123")
          end

          it "rejects strings that have extra lines before or after the `LocalTime` value (ensuring we are correctly matching against the entire string, not just one line)" do
            expect_input_value_to_be_rejected("a line\n00:00:00")
            expect_input_value_to_be_rejected("00:00:00\n a line")
            expect_input_value_to_be_rejected("a line\n00:00:00\n a line")
          end
        end

        context "result coercion" do
          it "returns a well-formatted time with hour 00 to 23" do
            0.upto(9) do |hour|
              expect_result_to_be_returned("0#{hour}:00:00")
            end

            10.upto(23) do |hour|
              expect_result_to_be_returned("#{hour}:00:00")
            end
          end

          it "returns `nil` in place of a time string with hours greater than 23" do
            24.upto(100) do |hour|
              expect_result_to_be_replaced_with_nil("#{hour}:00:00")
            end
          end

          it "returns a well-formatted time with minute 00 to 59" do
            0.upto(9) do |minute|
              expect_result_to_be_returned("00:0#{minute}:00")
            end

            10.upto(59) do |minute|
              expect_result_to_be_returned("00:#{minute}:00")
            end
          end

          it "returns `nil` in place of a time string with minutes greater than 59" do
            60.upto(100) do |minute|
              expect_result_to_be_replaced_with_nil("00:#{minute}0:00")
            end
          end

          it "returns a well-formatted time with second 00 to 59" do
            0.upto(9) do |second|
              expect_result_to_be_returned("00:00:0#{second}")
            end

            10.upto(59) do |second|
              expect_result_to_be_returned("00:00:#{second}")
            end
          end

          it "returns `nil` in place of a time string with seconds greater than 59" do
            60.upto(100) do |second|
              expect_result_to_be_replaced_with_nil("00:00:#{second}")
            end
          end

          it "returns `nil` in place of a time string with single-digit hour, minute, or second" do
            expect_result_to_be_replaced_with_nil("7:00:00")
            expect_result_to_be_replaced_with_nil("00:7:00")
            expect_result_to_be_replaced_with_nil("00:00:7")
          end

          it "returns up to 3 decimal subsecond digits" do
            expect_result_to_be_returned("00:00:00.1")
            expect_result_to_be_returned("00:00:00.12")
            expect_result_to_be_returned("00:00:00.123")
          end

          it "returns `nil` in place of a time string with malformed or too many decimal digits" do
            expect_result_to_be_replaced_with_nil("00:00:00.1a")
            expect_result_to_be_replaced_with_nil("00:00:00.")
            expect_result_to_be_replaced_with_nil("00:00:00.1234")
          end

          it "returns `nil` in place of non-string values" do
            expect_result_to_be_replaced_with_nil(3)
            expect_result_to_be_replaced_with_nil(3.7)
            expect_result_to_be_replaced_with_nil(true)
            expect_result_to_be_replaced_with_nil(false)
            expect_result_to_be_replaced_with_nil(["00:00:00"])
            expect_result_to_be_replaced_with_nil([])
          end

          it "returns `nil` in place of strings that are not formatted like a time at all" do
            expect_result_to_be_replaced_with_nil("not a time")
          end

          it "returns `nil` in place of strings that are not quite formatted correctly" do
            expect_result_to_be_replaced_with_nil("00:00") # no second part
            expect_result_to_be_replaced_with_nil("000000") # no colons
            expect_result_to_be_replaced_with_nil("07:00:00am") # am/pm
            expect_result_to_be_replaced_with_nil("07:00:00AM") # am/pm
            expect_result_to_be_replaced_with_nil("07:00:00 am") # am/pm
            expect_result_to_be_replaced_with_nil("07:00:00 AM") # am/pm
            expect_result_to_be_replaced_with_nil("07:00:00Z") # time zone
            expect_result_to_be_replaced_with_nil("07:00:00+03:00") # time zone offset
          end
        end
      end
    end
  end
end
