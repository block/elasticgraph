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
      RSpec.describe "TimeZone" do
        include_context "scalar coercion adapter support", "TimeZone"

        context "input coercion" do
          it "accepts valid time zone ids" do
            expect_input_value_to_be_accepted("America/Los_Angeles")
            expect_input_value_to_be_accepted("UTC")
          end

          it "accepts a `nil` value as-is" do
            expect_input_value_to_be_accepted(nil)
          end

          it "rejects values that are not strings" do
            expect_input_value_to_be_rejected(3)
            expect_input_value_to_be_rejected(3.7)
            expect_input_value_to_be_rejected(false)
            expect_input_value_to_be_rejected([1, 2, 3])
            expect_input_value_to_be_rejected(["a", "b"])
          end

          it "rejects empty strings" do
            expect_input_value_to_be_rejected("")
          end

          it "rejects unknown time zone ids" do
            expect_input_value_to_be_rejected("America/Seattle")
            expect_input_value_to_be_rejected("Who knows?")
          end

          it "suggests the corrected time zone if given one with a mistake" do
            expect_input_value_to_be_rejected("Japan/Tokyo", 'Possible alternative: "Asia/Tokyo".')
          end

          it "can offer two suggestions (X or Y)" do
            expect_input_value_to_be_rejected("Asia/Kathmando", 'Possible alternatives: "Asia/Kathmandu" or "Asia/Katmandu".')
          end

          it "can offer 3 or more suggestions (X, Y, or Z)" do
            # Note: we don't assert on the exact order of suggestions here because we found that it's different locally on Mac OS X vs on CI.
            expect_input_value_to_be_rejected("SystemV/BST3", "Possible alternatives:", '"SystemV/CST6", ', '"SystemV/YST9", ', '"SystemV/EST5",', ', or "SystemV/')
          end

          it "does not suggest anything if it cannot identify any suggestions" do
            expect_input_value_to_be_rejected("No Idea", expect_error_to_lack: ["Possible alternatives"])
          end
        end

        context "result coercion" do
          it "returns valid time zone ids" do
            expect_result_to_be_returned("America/Los_Angeles")
            expect_result_to_be_returned("UTC")
          end

          it "returns `nil` as is" do
            expect_result_to_be_returned(nil)
          end

          it "returns `nil` for non-string values" do
            expect_result_to_be_replaced_with_nil(3)
            expect_result_to_be_replaced_with_nil(3.7)
            expect_result_to_be_replaced_with_nil(false)
            expect_result_to_be_replaced_with_nil([1, 2, 3])
            expect_result_to_be_replaced_with_nil(["a", "b"])
          end

          it "returns `nil` for the empty string" do
            expect_result_to_be_replaced_with_nil("")
          end

          it "returns `nil` for unknown time zone ids" do
            expect_result_to_be_replaced_with_nil("America/Seattle")
            expect_result_to_be_replaced_with_nil("Who knows?")
          end
        end

        describe "VALID_TIME_ZONES" do
          it "is up-to-date with the list of time zones available on the JVM (since that's the list that Elasticsearch/OpenSearch use)" do
            expected_time_zones_file = `#{SPEC_ROOT}/../script/dump_time_zones --print`
            actual_time_zones_file = ::File.read(::File.join(SPEC_ROOT, "..", "lib", "elastic_graph", "graphql", "scalar_coercion_adapters", "valid_time_zones.rb"))

            # Verify the file is up to date. If out of date, run `script/dump_time_zones` to fix it.
            expect(actual_time_zones_file).to eq(expected_time_zones_file)
          end
        end
      end
    end
  end
end
