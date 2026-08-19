#!/usr/bin/env ruby
# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Benchmarks the per-field cost `QueryContext#matching_lookahead_error` (#1340) adds to every
# field resolution, for the overwhelmingly common query that never records a lookahead error.
#
# `Resolvers::GraphQLAdapterBuilder` calls `context.matching_lookahead_error` at the top of both
# resolver lambdas it builds, i.e. for effectively every field ElasticGraph resolves. This compares
# three variants of that call:
#
# - "before" — no call at all, i.e. `main` prior to #1340.
# - "unguarded" — #1340 as originally written: unconditionally builds `context.current_path`
#   (which allocates) before checking the (empty, in the common case) recorded-errors array.
# - "guarded" — the shipped fix: returns immediately, without building `current_path` or
#   allocating a `LookaheadErrors` collector, when no error was ever recorded for this query.
#
# Each variant is exercised through real `GraphQL::Schema#execute`, not a microbenchmark of the
# method in isolation, so the numbers reflect the added cost relative to total field-resolution
# time (schema/query overhead, hash allocation for the response, etc.), not the method alone.
#
# Run with:
#   bundle exec ruby benchmarks/graphql/lookahead_error_check.rb

require "benchmark/ips"
require "graphql"

# A stand-in for `ElasticGraph::GraphQL::LookaheadErrors`: never has any records in this benchmark
# (we're measuring the no-error-recorded path), but matches its real shape (`Array#find` over
# `@records`) so the "unguarded" variant pays the same cost that path pays in production.
class FakeLookaheadErrors
  def initialize
    @records = []
  end

  def matching_error_for(current_path)
    @records.find { |r| r.matches?(current_path) }
  end
end

class BeforeContext < ::GraphQL::Query::Context
end

class UnguardedContext < ::GraphQL::Query::Context
  def matching_lookahead_error
    current_path = self.current_path
    lookahead_errors.matching_error_for(current_path)
  end

  def lookahead_errors
    @lookahead_errors ||= FakeLookaheadErrors.new
  end
end

class GuardedContext < ::GraphQL::Query::Context
  def matching_lookahead_error
    return nil unless (lookahead_errors = @lookahead_errors)
    current_path = self.current_path
    lookahead_errors.matching_error_for(current_path)
  end
end

# Builds a schema with many leaf fields, whose resolvers call `context.matching_lookahead_error`
# (for `context_class`es that define it) before returning a static value, mirroring exactly what
# `GraphQLAdapterBuilder`'s resolver lambdas do around the actual resolver call.
def build_schema(context_class:, num_fields:, check_lookahead_error:)
  field_defs = (1..num_fields).map { |i| "f#{i}" }

  leaf_type = Class.new(::GraphQL::Schema::Object) do
    graphql_name "Leaf#{context_class}"
    field_defs.each do |name|
      field name, String, null: true
      define_method(name) do
        context.matching_lookahead_error if check_lookahead_error
        "value"
      end
    end
  end

  container_type = Class.new(::GraphQL::Schema::Object) do
    graphql_name "Container#{context_class}"
    field :leaf, leaf_type, null: true
    define_method(:leaf) do
      context.matching_lookahead_error if check_lookahead_error
      :leaf
    end
  end

  query_type = Class.new(::GraphQL::Schema::Object) do
    graphql_name "Query#{context_class}"
    field :container, container_type, null: true
    define_method(:container) do
      context.matching_lookahead_error if check_lookahead_error
      :container
    end
  end

  Class.new(::GraphQL::Schema) do
    query(query_type)
    context_class(context_class)
  end
end

# Builds a query selecting `num_leaves` leaf fields, aliasing repeatedly into the fixed
# `leaf_field_names` pool once `num_leaves` exceeds it--this is what lets `num_leaves` scale into
# the hundreds of thousands without needing a schema with that many distinct field definitions.
def build_query(num_leaves:, leaf_field_names:)
  selections = (0...num_leaves).map { |i| "  a#{i}: #{leaf_field_names[i % leaf_field_names.size]}" }.join("\n")
  <<~GRAPHQL
    query BenchQuery {
      container {
        leaf {
    #{selections}
        }
      }
    }
  GRAPHQL
end

# `num_fields` is the size of the schema's actual field-definition pool (kept small--building the
# schema itself, not just executing queries against it, has a real cost); `num_leaves` is how many
# times the benchmark query selects (via aliases) into that pool.
configs = [
  {label: "small", num_fields: 10, num_leaves: 5},
  {label: "medium", num_fields: 50, num_leaves: 25},
  {label: "large", num_fields: 150, num_leaves: 100},
  {label: "xlarge", num_fields: 500, num_leaves: 500},
  {label: "5000 leaves", num_fields: 50, num_leaves: 5_000},
  {label: "50000 leaves", num_fields: 50, num_leaves: 50_000},
  {label: "500000 leaves", num_fields: 50, num_leaves: 500_000}
]

configs.each do |config|
  leaf_field_names = (1..config[:num_fields]).map { |i| "f#{i}" }
  query_string = build_query(num_leaves: config[:num_leaves], leaf_field_names: leaf_field_names)

  before_schema = build_schema(context_class: BeforeContext, num_fields: config[:num_fields], check_lookahead_error: false)
  unguarded_schema = build_schema(context_class: UnguardedContext, num_fields: config[:num_fields], check_lookahead_error: true)
  guarded_schema = build_schema(context_class: GuardedContext, num_fields: config[:num_fields], check_lookahead_error: true)

  [before_schema, unguarded_schema, guarded_schema].each do |schema|
    result = schema.execute(query_string)
    abort "query is not valid — check benchmark setup: #{result["errors"]}" if result["errors"]
  end

  puts
  puts "=" * 70
  puts "#{config[:label]} — #{config[:num_leaves]} leaf fields resolved per query"
  puts "=" * 70

  Benchmark.ips do |x|
    x.config(time: 5, warmup: 2)

    x.report("before (no check, main)") { before_schema.execute(query_string) }
    x.report("unguarded (#1340 as written)") { unguarded_schema.execute(query_string) }
    x.report("guarded (shipped fix)") { guarded_schema.execute(query_string) }

    x.compare!
  end
end
