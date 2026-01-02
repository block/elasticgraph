# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "support/indexing_preparer"

module ElasticGraph
  class Indexer
    module IndexingPreparers
      RSpec.describe "DateTime" do
        include_context "indexing preparer support", "DateTime"

        it "normalizes a DateTime string with 2-digit milliseconds to 3-digit precision for consistent string comparison" do
          # This is critical for min/max value tracking which uses string comparison.
          # Without consistent precision, ".53Z" > ".531Z" in string comparison because 'Z' > '1'.
          expect(prepare_scalar_value("2021-06-10T12:30:00.53Z")).to eq("2021-06-10T12:30:00.530Z")
        end

        it "normalizes a DateTime string with 1-digit milliseconds to 3-digit precision" do
          expect(prepare_scalar_value("2021-06-10T12:30:00.5Z")).to eq("2021-06-10T12:30:00.500Z")
        end

        it "preserves a DateTime string that already has 3-digit milliseconds" do
          expect(prepare_scalar_value("2021-06-10T12:30:00.123Z")).to eq("2021-06-10T12:30:00.123Z")
        end

        it "adds milliseconds to a DateTime string with second precision" do
          expect(prepare_scalar_value("2021-06-10T12:30:00Z")).to eq("2021-06-10T12:30:00.000Z")
        end

        it "normalizes a DateTime string with timezone offset to UTC" do
          expect(prepare_scalar_value("2021-06-10T12:30:00.53-07:00")).to eq("2021-06-10T19:30:00.530Z")
        end

        it "leaves a `nil` value unchanged" do
          expect(prepare_scalar_value(nil)).to eq(nil)
        end

        it "applies the value coercion logic to each element of an array" do
          expect(prepare_array_values(["2021-06-10T12:30:00.53Z", "2021-06-10T12:30:00.5Z"])).to eq(
            ["2021-06-10T12:30:00.530Z", "2021-06-10T12:30:00.500Z"]
          )
          expect(prepare_array_values([nil, nil])).to eq([nil, nil])
        end

        it "respects the index-preparation logic recursively at each level of a nested array" do
          results = prepare_array_of_array_of_values([
            ["2021-06-10T12:30:00.53Z", "2021-06-10T12:30:00.123Z"],
            ["2021-06-10T12:30:00.5Z", "2021-06-10T12:30:00Z"],
            [nil, "2021-06-10T12:30:00.53Z"]
          ])

          expect(results).to eq([
            ["2021-06-10T12:30:00.530Z", "2021-06-10T12:30:00.123Z"],
            ["2021-06-10T12:30:00.500Z", "2021-06-10T12:30:00.000Z"],
            [nil, "2021-06-10T12:30:00.530Z"]
          ])
        end

        it "respects the index-preparation rule recursively at each level of an object within an array" do
          expect(prepare_array_of_objects_of_values(["2021-06-10T12:30:00.53Z", "2021-06-10T12:30:00.5Z"])).to eq(
            ["2021-06-10T12:30:00.530Z", "2021-06-10T12:30:00.500Z"]
          )
          expect(prepare_array_of_objects_of_values([nil, nil])).to eq([nil, nil])
        end

        it "returns an invalid DateTime string as-is, letting the datastore reject it" do
          expect(prepare_scalar_value("not-a-date")).to eq("not-a-date")
        end

        it "returns a non-string value as-is, letting the datastore reject it" do
          expect(prepare_scalar_value(12345)).to eq(12345)
        end

        it "returns nil unchanged when called directly" do
          # This tests the nil guard in `prepare_for_indexing` directly, since RecordPreparer
          # short-circuits nil values before calling the preparer.
          expect(DateTime.prepare_for_indexing(nil)).to be_nil
        end

        describe "string comparison consistency" do
          # These tests verify the core reason for DateTime normalization:
          # ensuring that string comparison via .compareTo() in Painless works correctly.

          it "ensures normalized timestamps compare correctly when the less precise one would have won incorrectly" do
            less_value = prepare_scalar_value("2021-06-10T12:30:00.53Z")   # Would be .53Z without normalization
            more_value = prepare_scalar_value("2021-06-10T12:30:00.531Z")  # .531Z

            # Without normalization: ".53Z" > ".531Z" because 'Z' > '1'
            # With normalization: ".530Z" < ".531Z" (correct!)
            expect(less_value < more_value).to be true
          end

          it "ensures normalized timestamps compare correctly for trailing zeros" do
            value_530 = prepare_scalar_value("2021-06-10T12:30:00.530Z")
            value_53 = prepare_scalar_value("2021-06-10T12:30:00.53Z")

            # Both should normalize to the same value
            expect(value_530).to eq(value_53)
          end
        end
      end
    end
  end
end
