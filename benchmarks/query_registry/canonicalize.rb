#!/usr/bin/env ruby
# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Benchmarks the canonicalization that `ClientData.canonical_query_string_from`
# applies to each definition of a query document before comparing it to the
# registered queries.
#
# We compare two ways of applying the two canonicalization steps (removing
# `@egLatencySlo` and sorting variable declarations):
#
#   - before: each step takes and returns a node, so a definition that needs
#     both steps is merged twice, and any operation with directives is merged
#     even when it has no `@egLatencySlo` to remove.
#   - after: each step returns the updated attribute (or `nil` if no update is
#     needed), so a definition is merged at most once, with only the updated
#     attributes. (graphql-ruby's `merge` builds an ivar name symbol for each
#     key it is given, so passing an unchanged attribute is not free.)
#
# We measure the canonicalization step alone and the full canonical query
# string (which also includes `to_query_string`, and dominates the cost).
#
# Run with:
#   bundle exec ruby benchmarks/query_registry/canonicalize.rb

require "benchmark/ips"
require "graphql"

EG_LATENCY_SLO = "eg_latency_slo"
OPERATION_DEFINITION = GraphQL::Language::Nodes::OperationDefinition

module Before
  def self.canonicalize(definition)
    with_sorted_variables(without_eg_latency_slo_directive(definition))
  end

  def self.without_eg_latency_slo_directive(definition)
    return definition if definition.directives.empty?
    definition.merge(directives: definition.directives.reject { |dir| dir.name == EG_LATENCY_SLO })
  end

  def self.with_sorted_variables(definition)
    return definition unless definition.is_a?(OPERATION_DEFINITION)
    return definition if definition.variables.size < 2
    definition.merge(variables: definition.variables.sort_by(&:name))
  end
end

module After
  def self.canonicalize(definition)
    return definition unless definition.is_a?(OPERATION_DEFINITION)

    updated_directives = without_eg_latency_slo(definition.directives)
    updated_variables = sorted_variables_of(definition.variables)

    if updated_directives && updated_variables
      definition.merge(directives: updated_directives, variables: updated_variables)
    elsif updated_directives
      definition.merge(directives: updated_directives)
    elsif updated_variables
      definition.merge(variables: updated_variables)
    else
      definition
    end
  end

  def self.without_eg_latency_slo(directives)
    return nil if directives.empty?
    updated_directives = directives.reject { |dir| dir.name == EG_LATENCY_SLO }
    updated_directives unless updated_directives.size == directives.size
  end

  def self.sorted_variables_of(variables)
    return nil if variables.size < 2
    variables.sort_by(&:name)
  end
end

def canonicalize_definitions(impl, document)
  document.definitions.map { |definition| impl.canonicalize(definition) }
end

def canonical_query_string(impl, document)
  document.merge(definitions: canonicalize_definitions(impl, document)).to_query_string
end

def build_query(variables:, directives:)
  variable_declarations = variables.zero? ? "" : "(#{(1..variables).map { |i| "$v#{variables - i}: String" }.join(", ")})"
  arguments = variables.zero? ? "" : "(#{(1..variables).map { |i| "a#{i}: $v#{i - 1}" }.join(", ")})"

  <<~GRAPHQL
    query BenchQuery#{variable_declarations} #{directives} {
      widgets#{arguments} {
        ...widgetFields
      }
    }

    fragment widgetFields on Widget {
      id
      name
      parts { id name }
    }
  GRAPHQL
end

configs = [
  {label: "no directives or variables", variables: 0, directives: ""},
  {label: "@egLatencySlo only", variables: 0, directives: "@eg_latency_slo(ms: 2000)"},
  {label: "other directive only", variables: 0, directives: "@some_directive"},
  {label: "5 variables only", variables: 5, directives: ""},
  {label: "@egLatencySlo and 5 variables", variables: 5, directives: "@eg_latency_slo(ms: 2000)"}
]

configs.each do |config|
  query_string = build_query(variables: config[:variables], directives: config[:directives])
  document = GraphQL.parse(query_string)

  puts
  puts "=" * 70
  puts config[:label]
  puts "=" * 70

  # Sanity check: both implementations must produce the same canonical form.
  unless canonical_query_string(Before, document) == canonical_query_string(After, document)
    abort "canonical query strings differ for #{config[:label]}: check benchmark setup"
  end

  {
    "canonicalize definitions" => :canonicalize_definitions,
    "canonical query string" => :canonical_query_string
  }.each do |measurement, method_name|
    Benchmark.ips do |x|
      x.config(time: 5, warmup: 2)

      x.report("#{measurement} (before)") { send(method_name, Before, document) }
      x.report("#{measurement} (after)") { send(method_name, After, document) }

      x.compare!
    end
  end
end
