# Copyright 2024 - 2025 Block, Inc.
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
      RSpec.describe "Integral types" do
        %w[Int JsonSafeLong LongString].each do |type|
          describe "for the `#{type}` type" do
            include_context "indexing preparer support", type

            it "coerces an integer-valued float to a true integer to satisfy the datastore (necessary since JSON schema doesn't validate this)" do
              expect(prepare_scalar_value(3.0)).to eq(3).and be_an ::Integer
            end

            it "leaves a true integer value unchanged" do
              expect(prepare_scalar_value(4)).to eq(4).and be_an ::Integer
            end

            it "leaves a `nil` value unchanged" do
              expect(prepare_scalar_value(nil)).to eq(nil)
            end

            it "applies the value coercion logic to each element of an array" do
              expect(prepare_array_values([1.0, 3.0, 5.0])).to eq([1, 3, 5]).and all be_an ::Integer
              expect(prepare_array_values([nil, nil])).to eq([nil, nil])
            end

            it "respects the index-preparation logic recursively at each level of a nested array" do
              results = prepare_array_of_array_of_values([
                [1.0, 2],
                [2.0, 3],
                [3.0, 4],
                [nil, 2]
              ])

              expect(results).to eq([[1, 2], [2, 3], [3, 4], [nil, 2]])
              expect(results.flatten.compact).to all be_an ::Integer
            end

            it "respects the index-preparation rule recursively at each level of an object within an array" do
              expect(prepare_array_of_objects_of_values([1.0, 3.0, 5.0])).to eq([1, 3, 5]).and all be_an ::Integer
              expect(prepare_array_of_objects_of_values([nil, nil])).to eq([nil, nil])
            end

            it "raises an exception when given a true floating point number" do
              expect {
                prepare_scalar_value(3.1)
              }.to raise_error Errors::IndexOperationError, a_string_including("3.1")
            end

            it "raises an exception when given a string integer" do
              expect {
                prepare_scalar_value("17")
              }.to raise_error Errors::IndexOperationError, a_string_including("17")
            end
          end
        end
      end
    end
  end
end
