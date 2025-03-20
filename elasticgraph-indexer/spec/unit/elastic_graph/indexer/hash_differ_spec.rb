# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/hash_differ"

module ElasticGraph
  class Indexer
    RSpec.describe HashDiffer do
      describe ".diff" do
        it "returns nil when given two identical hashes" do
          expect(HashDiffer.diff({a: 1}, {a: 1})).to eq nil
        end

        it "returns a multi line string describing the difference" do
          diff = HashDiffer.diff(
            {a: 1, b: 2, d: 5},
            {b: 3, c: 4, d: 5}
          )

          expect(diff).to eq(<<~EOS.chomp)
            - a: 1
            ~ b: `2` => `3`
            + c: 4
          EOS
        end

        it "ignores the kinds of differences specified in `ignore:`" do
          diff = HashDiffer.diff(
            {a: 1, b: 2, d: 5},
            {b: 3, c: 4, d: 5},
            ignore_ops: [:-, :~]
          )

          expect(diff).to eq(<<~EOS.chomp)
            + c: 4
          EOS
        end

        it "returns nil when all present diff ops are ignored" do
          expect(HashDiffer.diff({}, {a: 1}, ignore_ops: [:+])).to eq nil
        end
      end
    end
  end
end
