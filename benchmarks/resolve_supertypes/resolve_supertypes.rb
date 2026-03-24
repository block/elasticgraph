#!/usr/bin/env ruby
# frozen_string_literal: true

# Compares two approaches for recursively resolving interface supertypes
# with cycle detection:
#   1. Array-threading: passes an accumulating array through each recursive call
#   2. Enumerator: a lazy Enumerator yields interfaces depth-first; the caller
#      detects cycles via a single Set
#
# Run: ruby benchmarks/resolve_supertypes/resolve_supertypes.rb

require "benchmark/ips"
require "set"

# Minimal stand-in for an interface type with a name and parent interfaces.
Node = Data.define(:name, :parents)

def build_chain(depth)
  nodes = Array.new(depth) { |i| Node.new(name: "Interface#{i}", parents: []) }
  (0...depth - 1).each { |i| nodes[i].parents << nodes[i + 1] }
  nodes
end

# --- Approach 1: array-threading (original) -----------------------------------

def resolve_via_array_threading(node, chain = [node.name])
  node.parents.flat_map do |parent|
    raise "cycle" if chain.include?(parent.name)
    [parent] + resolve_via_array_threading(parent, chain + [parent.name]).to_a
  end.to_set
end

# --- Approach 2: lazy Enumerator (current) ------------------------------------

def lazy_parents(node)
  Enumerator.new do |y|
    node.parents.each do |parent|
      y << parent
      lazy_parents(parent).each { |p| y << p }
    end
  end
end

def resolve_via_enumerator(node)
  lazy_parents(node).each_with_object(Set.new) do |parent, seen|
    raise "cycle" unless seen.add?(parent)
  end
end

# --- Run benchmarks -----------------------------------------------------------

[3, 5, 10].each do |depth|
  nodes = build_chain(depth)
  root = nodes.first

  puts "\n=== Chain depth: #{depth} ==="
  Benchmark.ips do |x|
    x.report("array-threading") { resolve_via_array_threading(root) }
    x.report("enumerator")      { resolve_via_enumerator(root) }
    x.compare!
  end
end
