#!/usr/bin/env ruby
# frozen_string_literal: true

require "benchmark/ips"

# Test data
DEEP_HASH = {
  "level1" => {
    "level2" => {
      "level3" => {
        "level4" => {
          "value" => "found it!"
        }
      }
    }
  }
}

SHALLOW_HASH = {
  "key" => "value",
  "level1" => "not going deeper"
}

DEEP_PATH = %w[level1 level2 level3 level4 value]
SHALLOW_PATH = %w[key]

# Original implementation using reduce
def fetch_with_reduce(hash, path_parts)
  path_parts.each.with_index(1).reduce(hash) do |inner_hash, (key, num_parts)|
    if inner_hash.is_a?(::Hash)
      inner_hash.fetch(key) do
        missing_path = path_parts.first(num_parts)
        return yield missing_path if block_given?
        raise KeyError, "Key not found: #{missing_path.inspect}"
      end
    else
      raise KeyError, "Value at key #{path_parts.first(num_parts - 1).inspect} is not a `Hash` as expected; " \
        "instead, was a `#{inner_hash.class}`"
    end
  end
end

# Current implementation using each
def fetch_with_each(hash, path_parts)
  current = hash

  path_parts.each_with_index do |key, i|
    unless current.is_a?(Hash)
      raise KeyError, "Value at key #{path_parts.first(i).inspect} is not a `Hash` as expected; " \
        "instead, was a `#{current.class}`"
    end

    current = current.fetch(key) do
      missing_path = path_parts.first(i + 1)
      return yield missing_path if block_given?

      raise KeyError, "Key not found: #{missing_path.inspect}"
    end
  end

  current
end

# Alternative using dig with explicit type checking
def fetch_with_dig(hash, path_parts)
  current = hash
  last_key = path_parts.last
  parent_path = path_parts[0...-1]

  parent_path.each_with_index do |key, i|
    current = current.fetch(key) do
      missing_path = path_parts.first(i + 1)
      return yield missing_path if block_given?
      raise KeyError, "Key not found: #{missing_path.inspect}"
    end

    unless current.is_a?(Hash)
      raise KeyError, "Value at key #{path_parts.first(i).inspect} is not a `Hash` as expected; " \
        "instead, was a `#{current.class}`"
    end
  end

  current.fetch(last_key) do
    return yield path_parts if block_given?
    raise KeyError, "Key not found: #{path_parts.inspect}"
  end
end

# Alternative using while loop
def fetch_with_while(hash, path_parts)
  current = hash
  i = 0

  while i < path_parts.length
    key = path_parts[i]

    unless current.is_a?(Hash)
      raise KeyError, "Value at key #{path_parts.first(i).inspect} is not a `Hash` as expected; " \
        "instead, was a `#{current.class}`"
    end

    current = current.fetch(key) do
      missing_path = path_parts.first(i + 1)
      return yield missing_path if block_given?
      raise KeyError, "Key not found: #{missing_path.inspect}"
    end

    i += 1
  end

  current
end

# Alternative using recursion
def fetch_with_recursion(hash, path_parts, index = 0)
  return hash if index == path_parts.length

  unless hash.is_a?(Hash)
    raise KeyError, "Value at key #{path_parts.first(index).inspect} is not a `Hash` as expected; " \
      "instead, was a `#{hash.class}`"
  end

  key = path_parts[index]
  value = hash.fetch(key) do
    missing_path = path_parts.first(index + 1)
    return yield missing_path if block_given?
    raise KeyError, "Key not found: #{missing_path.inspect}"
  end

  fetch_with_recursion(value, path_parts, index + 1)
end

# Special case implementation for single key
def fetch_single_key(hash, path_parts)
  unless hash.is_a?(Hash)
    raise KeyError, "Value is not a `Hash` as expected; instead, was a `#{hash.class}`"
  end

  hash.fetch(path_parts.first) do
    return yield path_parts if block_given?
    raise KeyError, "Key not found: #{path_parts.inspect}"
  end
end

puts "Benchmarking deep path (#{DEEP_PATH.length} levels)..."
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("reduce - deep") { fetch_with_reduce(DEEP_HASH, DEEP_PATH) }
  x.report("each - deep") { fetch_with_each(DEEP_HASH, DEEP_PATH) }
  x.report("dig - deep") { fetch_with_dig(DEEP_HASH, DEEP_PATH) }
  x.report("while - deep") { fetch_with_while(DEEP_HASH, DEEP_PATH) }
  x.report("recursion - deep") { fetch_with_recursion(DEEP_HASH, DEEP_PATH) }

  x.compare!
end

puts "\nBenchmarking shallow path (single key - most common case)..."
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("reduce - shallow") { fetch_with_reduce(SHALLOW_HASH, SHALLOW_PATH) }
  x.report("each - shallow") { fetch_with_each(SHALLOW_HASH, SHALLOW_PATH) }
  x.report("dig - shallow") { fetch_with_dig(SHALLOW_HASH, SHALLOW_PATH) }
  x.report("while - shallow") { fetch_with_while(SHALLOW_HASH, SHALLOW_PATH) }
  x.report("recursion - shallow") { fetch_with_recursion(SHALLOW_HASH, SHALLOW_PATH) }
  x.report("single key") { fetch_single_key(SHALLOW_HASH, SHALLOW_PATH) }

  x.compare!
end

# Also test error cases
ERROR_HASH = {"level1" => "not a hash"}
ERROR_PATH = %w[level1 level2]

puts "\nBenchmarking error cases..."
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("reduce - error") {
    begin
      fetch_with_reduce(ERROR_HASH, ERROR_PATH)
    rescue
      nil
    end
  }
  x.report("each - error") {
    begin
      fetch_with_each(ERROR_HASH, ERROR_PATH)
    rescue
      nil
    end
  }
  x.report("dig - error") {
    begin
      fetch_with_dig(ERROR_HASH, ERROR_PATH)
    rescue
      nil
    end
  }
  x.report("while - error") {
    begin
      fetch_with_while(ERROR_HASH, ERROR_PATH)
    rescue
      nil
    end
  }
  x.report("recursion - error") {
    begin
      fetch_with_recursion(ERROR_HASH, ERROR_PATH)
    rescue
      nil
    end
  }

  x.compare!
end
