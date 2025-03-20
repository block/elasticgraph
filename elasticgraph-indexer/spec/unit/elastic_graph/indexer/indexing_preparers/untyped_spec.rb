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
      RSpec.describe "Untyped" do
        include_context "indexing preparer support", "Untyped"

        it "dumps an integer as a string so it can be indexed as a keyword" do
          expect(prepare_scalar_value(3)).to eq "3"
        end

        it "dumps a float as a string so it can be indexed as a keyword" do
          expect(prepare_scalar_value(3.14)).to eq "3.14"
        end

        it "drops excess zeroes on a float to convert it to a canonical form" do
          expect(prepare_scalar_value(3.2100000)).to eq("3.21")
        end

        it "dumps a boolean as a string so it can be indexed as a keyword" do
          expect(prepare_scalar_value(true)).to eq "true"
          expect(prepare_scalar_value(false)).to eq "false"
        end

        it "quotes strings so that it is parseable as JSON" do
          expect(prepare_scalar_value("true")).to eq '"true"'
          expect(prepare_scalar_value("3")).to eq '"3"'
        end

        it "dumps `nil` as `nil` so that the index field remains unset" do
          expect(prepare_scalar_value(nil, validate_roundtrip: false)).to eq nil
        end

        it "dumps an array as a compact JSON string so it can be indexed as a keyword" do
          expect(prepare_scalar_value([1, true, "hello"])).to eq('[1,true,"hello"]')
        end

        it "dumps an array as a compact JSON string so it can be indexed as a keyword" do
          expect(prepare_scalar_value([1, true, "hello"])).to eq('[1,true,"hello"]')
        end

        it "orders object keys alphabetically when dumping it to normalize to a canonical form" do
          expect(prepare_scalar_value({"b" => 1, "a" => 2, "c" => 3})).to eq('{"a":2,"b":1,"c":3}')
        end

        # Override `prepare_scalar_value` to enforce an invariant: parsing the resulting JSON string
        # should always produce the original value
        prepend Module.new {
          def prepare_scalar_value(original_value, validate_roundtrip: true)
            super(original_value).tap do |prepared_value|
              if validate_roundtrip
                expect(::JSON.parse(prepared_value)).to eq(original_value)
              end
            end
          end
        }
      end
    end
  end
end
