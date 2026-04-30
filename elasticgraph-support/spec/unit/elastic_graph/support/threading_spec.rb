# Copyright 2024 - 2026 Block, Inc.
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

        it "does not spawn a thread when there is only one item to map" do
          calling_thread = Thread.current

          result = Threading.parallel_map(["a"]) do |value|
            expect(Thread.current).to be(calling_thread)
            value.next
          end

          expect(result).to eq ["b"]
        end

        it "preserves hash entry destructuring when there is only one item to map" do
          calling_thread = Thread.current

          result = Threading.parallel_map({"a" => 1}) do |key, value|
            expect(Thread.current).to be(calling_thread)
            [key.next, value.next]
          end

          expect(result).to eq [["b", 2]]
        end

        it "preserves the backtrace on exceptions when mapping over one item" do
          exception1 = ["a"].map { raise it } rescue $! # standard:disable Style/RescueModifier
          exception2 = Threading.parallel_map(["a"]) { raise it } rescue $! # standard:disable Style/RescueModifier

          spec_file = File.basename(__FILE__)

          suffix1, suffix2 = [exception1, exception2].map do |ex|
            ex.backtrace
              .reject { |frame| frame.include?(spec_file) || frame.include?("threading.rb") }
              .join("\n")
          end

          # Threading.parallel_map updates exception backtraces normally.
          # Here we confirm it has not changed backtraces for the non-threaded fast path.
          expect(suffix2).to eq(suffix1)
        end

        it "uses threads when mapping over multiple hash entries" do
          calling_thread = Thread.current

          result = Threading.parallel_map({"a" => 1, "b" => 2}) do |key, value|
            expect(Thread.current).not_to be(calling_thread)
            [key.next, value.next]
          end

          expect(result).to eq [["b", 2], ["c", 3]]
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
