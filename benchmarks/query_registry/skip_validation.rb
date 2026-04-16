#!/usr/bin/env ruby
# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Benchmarks the cost of graphql-ruby's `StaticValidation` pipeline against the
# cache-hit path in `ForRegisteredClient#prepare_query_for_execution`, which now
# passes `validate: false` to skip that pipeline for registered queries.
#
# We compare, for a pre-parsed document, the cost of building a query and
# triggering its validation pipeline with `validate: true` (the former
# behavior) vs `validate: false` (the new behavior for cache hits).
#
# Run with:
#   bundle exec ruby benchmarks/query_registry/skip_validation.rb

require "benchmark/ips"
require "graphql"

# Build a schema with many fields, so queries can be meaningfully sized.
def build_schema(num_fields:)
  field_defs = (1..num_fields).map { |i| "f#{i}" }

  leaf_type = Class.new(GraphQL::Schema::Object) do
    graphql_name "Leaf"
    field_defs.each { |name| field name, String, null: true }
  end

  container_type = Class.new(GraphQL::Schema::Object) do
    graphql_name "Container"
    field :leaf, leaf_type, null: true
    field_defs.each { |name| field name, leaf_type, null: true }
  end

  query_type = Class.new(GraphQL::Schema::Object) do
    graphql_name "Query"
    field :container, container_type, null: true
    field :leaf, leaf_type, null: true
  end

  Class.new(GraphQL::Schema) do
    query(query_type)
  end
end

# Build a query string of approximately the requested size by selecting all
# leaf fields under nested containers.
def build_query(num_leaves:, leaf_field_names:)
  selections = leaf_field_names.take(num_leaves).map { |f| "  #{f}" }.join("\n")
  <<~GRAPHQL
    query BenchQuery {
      container {
        leaf {
    #{selections}
        }
    #{leaf_field_names.take(num_leaves).map { |f|
      "    #{f} {\n#{selections}\n    }"
    }.join("\n")}
      }
    }
  GRAPHQL
end

configs = [
  {label: "small", num_fields: 10, num_leaves: 5},
  {label: "medium", num_fields: 50, num_leaves: 25},
  {label: "large", num_fields: 150, num_leaves: 100},
  {label: "xlarge", num_fields: 300, num_leaves: 250}
]

configs.each do |config|
  schema = build_schema(num_fields: config[:num_fields])
  leaf_field_names = (1..config[:num_fields]).map { |i| "f#{i}" }
  query_string = build_query(num_leaves: config[:num_leaves], leaf_field_names: leaf_field_names)
  document = GraphQL.parse(query_string)

  puts
  puts "=" * 70
  puts "#{config[:label]} — #{query_string.bytesize} bytes, #{query_string.lines.count} lines"
  puts "=" * 70

  # Sanity check: both paths should produce a valid query.
  valid_query = GraphQL::Query.new(schema, nil, document: document, validate: true)
  skipped_query = GraphQL::Query.new(schema, nil, document: document, validate: false)
  unless valid_query.valid? && skipped_query.valid?
    abort "query is not valid — check benchmark setup: #{valid_query.static_errors.map(&:message)}"
  end

  Benchmark.ips do |x|
    x.config(time: 5, warmup: 2)

    x.report("validate: true (before)") do
      q = GraphQL::Query.new(schema, nil, document: document, validate: true)
      q.valid?
    end

    x.report("validate: false (after)") do
      q = GraphQL::Query.new(schema, nil, document: document, validate: false)
      q.valid?
    end

    x.compare!
  end
end
