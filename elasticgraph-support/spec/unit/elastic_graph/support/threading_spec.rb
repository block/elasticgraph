# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/threading"

module ElasticGraph
  module Support
    RSpec.describe Threading do
      describe ".parallel_map" do
        it "maps over the given array just like `Enumerable#map`" do
          result = Threading.parallel_map(%w[a b c], &:next)
          expect(result).to eq %w[b c d]
        end

        it "propagates exceptions to the calling thread properly, even preserving the calling thread's stacktrace in the exception" do
          expected_trace_frames = caller

          expect {
            Threading.parallel_map([1, 2, 3]) do |num|
              raise "boom" if num.even?
              num * 2
            end
          }.to raise_error { |ex|
            expect(ex.message).to eq "boom"
            expect(ex.backtrace).to end_with(expected_trace_frames)
          }.and avoid_outputting.to_stdout.and avoid_outputting.to_stderr
        end
      end
    end
  end
end
