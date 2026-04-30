#!/usr/bin/env ruby
# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Benchmarks the single-item fast path in ElasticGraph::Support::Threading.parallel_map
# using local copies of the before/after implementations.
#
# Run with:
#   bundle exec ruby benchmarks/threading/parallel_map_single_item.rb

require "benchmark/ips"

module OriginalThreadingImplementation
  def self.parallel_map(items)
    threads = _ = items.map do |item|
      ::Thread.new do
        ::Thread.current.report_on_exception = false

        yield item
      end
    end

    threads.map(&:value)
  rescue => e
    e.set_backtrace(e.backtrace + caller)
    raise e
  end
end

module UpdatedThreadingImplementation
  def self.parallel_map(items)
    return _ = items.map { |item| yield item } if items.size < 2

    begin
      threads = _ = items.map do |item|
        ::Thread.new do
          ::Thread.current.report_on_exception = false

          yield item
        end
      end

      threads.map(&:value)
    rescue => e
      e.set_backtrace(e.backtrace + caller)
      raise e
    end
  end
end

SINGLE_ARRAY = ["a"].freeze
EMPTY_ARRAY = [].freeze
MULTI_ITEM_ARRAY = %w[a b c d].freeze
SINGLE_HASH = {"orders" => [1, 2, 3]}.freeze
EMPTY_HASH = {}.freeze
MULTI_ENTRY_HASH = {
  "orders" => [1, 2, 3],
  "payments" => [4, 5, 6],
  "refunds" => [7, 8, 9],
  "disputes" => [10, 11, 12]
}.freeze

def updated_parallel_map(items, &block)
  UpdatedThreadingImplementation.parallel_map(items, &block)
end

def assert_same_result(label)
  original = yield OriginalThreadingImplementation
  updated = yield UpdatedThreadingImplementation

  abort "#{label} produced different results: #{original.inspect} != #{updated.inspect}" unless original == updated
end

assert_same_result("single array") { |implementation| implementation.parallel_map(SINGLE_ARRAY, &:next) }
assert_same_result("empty array") { |implementation| implementation.parallel_map(EMPTY_ARRAY, &:next) }
assert_same_result("multi item array") { |implementation| implementation.parallel_map(MULTI_ITEM_ARRAY, &:next) }
assert_same_result("single hash") { |implementation| implementation.parallel_map(SINGLE_HASH) { |key, values| [key, values.size] } }
assert_same_result("empty hash") { |implementation| implementation.parallel_map(EMPTY_HASH) { |key, values| [key, values.size] } }
assert_same_result("multi entry hash") do |implementation|
  implementation.parallel_map(MULTI_ENTRY_HASH) { |key, values| [key, values.size] }
end

def run_ips(title)
  puts
  puts "=" * 80
  puts title
  puts "=" * 80

  Benchmark.ips do |x|
    x.config(time: 5, warmup: 2)
    yield x
    x.compare!
  end
end

run_ips("single item array") do |x|
  x.report("before: always spawn thread") { OriginalThreadingImplementation.parallel_map(SINGLE_ARRAY, &:next) }
  x.report("after: fast path") { updated_parallel_map(SINGLE_ARRAY, &:next) }
end

run_ips("single entry hash, like one datastore-client msearch fanout") do |x|
  x.report("before: always spawn thread") do
    OriginalThreadingImplementation.parallel_map(SINGLE_HASH) { |key, values| [key, values.size] }
  end

  x.report("after: fast path") do
    updated_parallel_map(SINGLE_HASH) { |key, values| [key, values.size] }
  end
end

run_ips("empty array") do |x|
  x.report("before: always spawn thread") { OriginalThreadingImplementation.parallel_map(EMPTY_ARRAY, &:next) }
  x.report("after: fast path") { updated_parallel_map(EMPTY_ARRAY, &:next) }
end

run_ips("empty hash") do |x|
  x.report("before: always spawn thread") do
    OriginalThreadingImplementation.parallel_map(EMPTY_HASH) { |key, values| [key, values.size] }
  end

  x.report("after: fast path") do
    updated_parallel_map(EMPTY_HASH) { |key, values| [key, values.size] }
  end
end

run_ips("multi item array, expected to stay on the threaded path") do |x|
  x.report("before: always spawn thread") { OriginalThreadingImplementation.parallel_map(MULTI_ITEM_ARRAY, &:next) }
  x.report("after: current implementation") { updated_parallel_map(MULTI_ITEM_ARRAY, &:next) }
end

run_ips("multi entry hash, expected to stay on the threaded path") do |x|
  x.report("before: always spawn thread") do
    OriginalThreadingImplementation.parallel_map(MULTI_ENTRY_HASH) { |key, values| [key, values.size] }
  end

  x.report("after: current implementation") do
    updated_parallel_map(MULTI_ENTRY_HASH) { |key, values| [key, values.size] }
  end
end

module ThreadNewCounter
  def self.count
    @count ||= 0
  end

  def self.count=(count)
    @count = count
  end

  def new(...)
    ThreadNewCounter.count += 1
    super
  end
end

class << Thread
  prepend ThreadNewCounter
end

def count_thread_new_calls
  ThreadNewCounter.count = 0
  yield
  ThreadNewCounter.count
end

thread_count_iterations = 1_000

puts
puts "Thread.new calls for #{thread_count_iterations} map calls"
puts "-" * 80
{
  "before single array" => -> { OriginalThreadingImplementation.parallel_map(SINGLE_ARRAY, &:next) },
  "after single array" => -> { updated_parallel_map(SINGLE_ARRAY, &:next) },
  "before single hash" => -> { OriginalThreadingImplementation.parallel_map(SINGLE_HASH) { |key, values| [key, values.size] } },
  "after single hash" => -> { updated_parallel_map(SINGLE_HASH) { |key, values| [key, values.size] } },
  "before empty array" => -> { OriginalThreadingImplementation.parallel_map(EMPTY_ARRAY, &:next) },
  "after empty array" => -> { updated_parallel_map(EMPTY_ARRAY, &:next) },
  "before empty hash" => -> { OriginalThreadingImplementation.parallel_map(EMPTY_HASH) { |key, values| [key, values.size] } },
  "after empty hash" => -> { updated_parallel_map(EMPTY_HASH) { |key, values| [key, values.size] } },
  "before multi item array" => -> { OriginalThreadingImplementation.parallel_map(MULTI_ITEM_ARRAY, &:next) },
  "after multi item array" => -> { updated_parallel_map(MULTI_ITEM_ARRAY, &:next) },
  "before multi entry hash" => -> { OriginalThreadingImplementation.parallel_map(MULTI_ENTRY_HASH) { |key, values| [key, values.size] } },
  "after multi entry hash" => -> { updated_parallel_map(MULTI_ENTRY_HASH) { |key, values| [key, values.size] } }
}.each do |label, callable|
  count = count_thread_new_calls do
    thread_count_iterations.times { callable.call }
  end

  puts "#{label.ljust(28)} #{count}"
end
