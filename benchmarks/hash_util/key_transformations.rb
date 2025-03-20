#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require "memory_profiler"

# This benchmark compares different approaches to the recursive transformation
# of hash keys, focusing on stringify_keys and symbolize_keys which are the
# main consumers of the recursively_transform method.
module ElasticGraph
  module Support
    module HashUtilOriginal
      def self.stringify_keys(object)
        recursively_transform(object) do |key, value, hash|
          hash[key.to_s] = value
        end
      end

      def self.symbolize_keys(object)
        recursively_transform(object) do |key, value, hash|
          hash[key.to_sym] = value
        end
      end

      private_class_method def self.recursively_transform(object, key_path = nil, &hash_entry_handler)
        case object
        when ::Hash
          # @type var initial: ::Hash[key, value]
          initial = {}
          object.each_with_object(initial) do |(key, value), hash|
            updated_path = key_path ? "#{key_path}.#{key}" : key.to_s
            value = recursively_transform(value, updated_path, &hash_entry_handler)
            hash_entry_handler.call(key, value, hash, updated_path)
          end
        when ::Array
          object.map.with_index do |item, index|
            recursively_transform(item, "#{key_path}[#{index}]", &hash_entry_handler)
          end
        else
          object
        end
      end
    end

    module HashUtilOptimizedV1
      def self.stringify_keys(object)
        case object
        when ::Hash
          object.each_with_object({}) do |(key, value), hash|
            hash[key.to_s] = stringify_keys(value)
          end
        when ::Array
          object.map { |item| stringify_keys(item) }
        else
          object
        end
      end

      def self.symbolize_keys(object)
        case object
        when ::Hash
          object.each_with_object({}) do |(key, value), hash|
            hash[key.to_sym] = symbolize_keys(value)
          end
        when ::Array
          object.map { |item| symbolize_keys(item) }
        else
          object
        end
      end
    end

    module HashUtilOptimizedV2
      def self.stringify_keys(object)
        transform_keys(object, :to_s)
      end

      def self.symbolize_keys(object)
        transform_keys(object, :to_sym)
      end

      private_class_method def self.transform_keys(object, method)
        case object
        when ::Hash
          result = {}
          object.each do |key, value|
            result[key.send(method)] = transform_keys(value, method)
          end
          result
        when ::Array
          object.map { |item| transform_keys(item, method) }
        else
          object
        end
      end
    end

    module HashUtilOptimizedV3
      def self.stringify_keys(object)
        transform_keys(object, :to_s)
      end

      def self.symbolize_keys(object)
        transform_keys(object, :to_sym)
      end

      private_class_method def self.transform_keys(object, method)
        case object
        when ::Hash
          object.to_h do |key, value|
            [key.send(method), transform_keys(value, method)]
          end
        when ::Array
          object.map { |item| transform_keys(item, method) }
        else
          object
        end
      end
    end

    class RecursiveTransformBenchmark
      SIMPLE_HASH = {foo: 1, bar: 2, bazz: 3}
      STRING_HASH = {"foo" => 1, "bar" => 2, "bazz" => 3}

      NESTED_HASH = {
        foo: {
          bar: {
            bazz: [1, 2, 3],
            other: {
              deep: "value"
            }
          },
          other: 2
        },
        top: "level"
      }
      NESTED_STRING_HASH = {
        "foo" => {
          "bar" => {
            "bazz" => [1, 2, 3],
            "other" => {
              "deep" => "value"
            }
          },
          "other" => 2
        },
        "top" => "level"
      }

      ARRAY_HEAVY_HASH = {
        items: [
          {id: 1, tags: ["a", "b", "c"]},
          {id: 2, tags: ["d", "e", "f"]},
          {id: 3, tags: ["g", "h", "i"]},
          {id: 4, tags: ["j", "k", "l"]}
        ],
        metadata: {
          counts: [1, 2, 3],
          nested: [
            {x: 1, y: 2},
            {x: 3, y: 4}
          ]
        }
      }
      ARRAY_HEAVY_STRING_HASH = {
        "items" => [
          {"id" => 1, "tags" => ["a", "b", "c"]},
          {"id" => 2, "tags" => ["d", "e", "f"]},
          {"id" => 3, "tags" => ["g", "h", "i"]},
          {"id" => 4, "tags" => ["j", "k", "l"]}
        ],
        "metadata" => {
          "counts" => [1, 2, 3],
          "nested" => [
            {"x" => 1, "y" => 2},
            {"x" => 3, "y" => 4}
          ]
        }
      }

      def self.verify_implementations
        puts "\nVerifying implementations return the same results..."

        test_cases = [
          [:stringify_keys, SIMPLE_HASH],
          [:stringify_keys, NESTED_HASH],
          [:stringify_keys, ARRAY_HEAVY_HASH],
          [:symbolize_keys, STRING_HASH],
          [:symbolize_keys, NESTED_STRING_HASH],
          [:symbolize_keys, ARRAY_HEAVY_STRING_HASH]
        ]

        implementations = [
          HashUtilOriginal,
          HashUtilOptimizedV1,
          HashUtilOptimizedV2,
          HashUtilOptimizedV3
        ]

        test_cases.each do |method, input|
          results = implementations.map { |impl| impl.send(method, input) }
          if results.uniq.size != 1
            puts "❌ Mismatch for #{method} with #{input.class}:"
            results.each_with_index do |result, i|
              puts "  #{implementations[i].name}: #{result.inspect}"
            end
            return false
          end
        end

        puts "✅ All implementations return the same results"
        true
      end

      def self.run_benchmarks
        return unless verify_implementations

        puts "\nRunning performance benchmarks..."

        Benchmark.ips do |x|
          x.config(time: 5, warmup: 2)

          # Stringify keys benchmarks
          x.report("original stringify - simple") do
            HashUtilOriginal.stringify_keys(SIMPLE_HASH)
          end

          x.report("optimized1 stringify - simple") do
            HashUtilOptimizedV1.stringify_keys(SIMPLE_HASH)
          end

          x.report("optimized2 stringify - simple") do
            HashUtilOptimizedV2.stringify_keys(SIMPLE_HASH)
          end

          x.report("optimized3 stringify - simple") do
            HashUtilOptimizedV3.stringify_keys(SIMPLE_HASH)
          end

          x.report("original stringify - nested") do
            HashUtilOriginal.stringify_keys(NESTED_HASH)
          end

          x.report("optimized1 stringify - nested") do
            HashUtilOptimizedV1.stringify_keys(NESTED_HASH)
          end

          x.report("optimized2 stringify - nested") do
            HashUtilOptimizedV2.stringify_keys(NESTED_HASH)
          end

          x.report("optimized3 stringify - nested") do
            HashUtilOptimizedV3.stringify_keys(NESTED_HASH)
          end

          x.report("original stringify - array heavy") do
            HashUtilOriginal.stringify_keys(ARRAY_HEAVY_HASH)
          end

          x.report("optimized1 stringify - array heavy") do
            HashUtilOptimizedV1.stringify_keys(ARRAY_HEAVY_HASH)
          end

          x.report("optimized2 stringify - array heavy") do
            HashUtilOptimizedV2.stringify_keys(ARRAY_HEAVY_HASH)
          end

          x.report("optimized3 stringify - array heavy") do
            HashUtilOptimizedV3.stringify_keys(ARRAY_HEAVY_HASH)
          end

          # Symbolize keys benchmarks
          x.report("original symbolize - simple") do
            HashUtilOriginal.symbolize_keys(STRING_HASH)
          end

          x.report("optimized1 symbolize - simple") do
            HashUtilOptimizedV1.symbolize_keys(STRING_HASH)
          end

          x.report("optimized2 symbolize - simple") do
            HashUtilOptimizedV2.symbolize_keys(STRING_HASH)
          end

          x.report("optimized3 symbolize - simple") do
            HashUtilOptimizedV3.symbolize_keys(STRING_HASH)
          end

          x.report("original symbolize - nested") do
            HashUtilOriginal.symbolize_keys(NESTED_STRING_HASH)
          end

          x.report("optimized1 symbolize - nested") do
            HashUtilOptimizedV1.symbolize_keys(NESTED_STRING_HASH)
          end

          x.report("optimized2 symbolize - nested") do
            HashUtilOptimizedV2.symbolize_keys(NESTED_STRING_HASH)
          end

          x.report("optimized3 symbolize - nested") do
            HashUtilOptimizedV3.symbolize_keys(NESTED_STRING_HASH)
          end

          x.report("original symbolize - array heavy") do
            HashUtilOriginal.symbolize_keys(ARRAY_HEAVY_STRING_HASH)
          end

          x.report("optimized1 symbolize - array heavy") do
            HashUtilOptimizedV1.symbolize_keys(ARRAY_HEAVY_STRING_HASH)
          end

          x.report("optimized2 symbolize - array heavy") do
            HashUtilOptimizedV2.symbolize_keys(ARRAY_HEAVY_STRING_HASH)
          end

          x.report("optimized3 symbolize - array heavy") do
            HashUtilOptimizedV3.symbolize_keys(ARRAY_HEAVY_STRING_HASH)
          end

          x.compare!
        end

        puts "\nRunning memory allocation analysis..."

        report = MemoryProfiler.report do
          50.times do
            HashUtilOriginal.stringify_keys(ARRAY_HEAVY_HASH)
            HashUtilOriginal.symbolize_keys(ARRAY_HEAVY_STRING_HASH)
          end
        end

        puts "\nOriginal implementation memory profile:"
        report.pretty_print(scale_bytes: true)

        report = MemoryProfiler.report do
          50.times do
            HashUtilOptimizedV2.stringify_keys(ARRAY_HEAVY_HASH)
            HashUtilOptimizedV2.symbolize_keys(ARRAY_HEAVY_STRING_HASH)
          end
        end

        puts "\nOptimized implementation memory profile:"
        report.pretty_print(scale_bytes: true)
      end
    end
  end
end

ElasticGraph::Support::RecursiveTransformBenchmark.run_benchmarks
