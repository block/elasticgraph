# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/untyped_encoder"

module ElasticGraph
  module Support
    RSpec.describe UntypedEncoder do
      it "dumps an integer as a string so it can be indexed as a keyword" do
        expect(encode(3)).to eq "3"
      end

      it "dumps a float as a string so it can be indexed as a keyword" do
        expect(encode(3.14)).to eq "3.14"
      end

      it "drops excess zeroes on a float to convert it to a canonical form" do
        expect(encode(3.2100000)).to eq("3.21")
      end

      it "dumps a boolean as a string so it can be indexed as a keyword" do
        expect(encode(true)).to eq "true"
        expect(encode(false)).to eq "false"
      end

      it "quotes strings so that it is parseable as JSON" do
        expect(encode("true")).to eq '"true"'
        expect(encode("3")).to eq '"3"'
      end

      it "dumps `nil` as `nil` so that the index field remains unset" do
        expect(encode(nil)).to eq nil
      end

      it "dumps an array as a compact JSON string so it can be indexed as a keyword" do
        expect(encode([1, true, "hello"])).to eq('[1,true,"hello"]')
      end

      it "dumps an array as a compact JSON string so it can be indexed as a keyword" do
        expect(encode([1, true, "hello"])).to eq('[1,true,"hello"]')
      end

      it "orders object keys alphabetically when dumping it to normalize to a canonical form" do
        expect(encode({"b" => 1, "a" => 2, "c" => 3})).to eq('{"a":2,"b":1,"c":3}')
      end

      it "applies the hash key sorting recursively at any level of the structure" do
        data = ["f", {"b" => 1, "a" => [{"d" => 3, "c" => 2}]}]
        expect(encode(data)).to eq('["f",{"a":[{"c":2,"d":3}],"b":1}]')
      end

      it "can apply hash key sorting even when the keys are of different types" do
        data = {"a" => 1, 3 => "b", 2 => "d"}

        # JSON doesn't support keys that aren't strings, but JSON.generate converts keys to strings.
        expect(::JSON.generate(data)).to eq('{"a":1,"3":"b","2":"d"}')
        # 3 and "a" aren't comparable when sorting...
        expect { data.keys.sort }.to raise_error(/comparison of String with (2|3) failed/)
        # ...but encode is still able to sort them.
        #
        # Note: JSON objects don't support non-string keys, so we should never actually hit this case,
        # but we don't want our sorting canonicalization logic to introduce exceptions, so we handle this
        # case (and cover it with a test).
        expect(encode(data, validate_roundtrip: false)).to eq('{"2":"d","3":"b","a":1}')
      end

      # This helper method enforces  an invariant: parsing the resulting JSON string
      # should always produce the original value
      def encode(original_value, validate_roundtrip: true)
        UntypedEncoder.encode(original_value).tap do |prepared_value|
          if validate_roundtrip
            expect(UntypedEncoder.decode(prepared_value)).to eq(original_value)
          end
        end
      end
    end
  end
end
