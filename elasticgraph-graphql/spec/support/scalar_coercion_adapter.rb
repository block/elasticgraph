# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/graphql_formatter"
require "elastic_graph/support/hash_util"
require "graphql"

# Provides test harness support for testing scalar coercion adapters. Makes
# it easy to exercise the `coerce_input`/`coerce_result` methods of
# a scalar adapter and see how that behavior is visible from a client's
# point of view.
RSpec.shared_context "scalar coercion adapter support" do |scalar_type_name, schema_definition: nil|
  before(:context) do
    normal_graphql_adapter = build_graphql(schema_definition: schema_definition, clients_by_name: {}).graphql_adapter
    @test_resolver = ScalarCoercionAdapterTestResolver.new

    test_adapter = ElasticGraph::Support::HashUtil.deep_merge(
      normal_graphql_adapter,
      {
        "Query" => {
          "echo" => ->(object, args, context) {
            @test_resolver.call(object, args, context)
          }
        }
      }
    )

    @graphql = build_graphql(graphql_adapter: test_adapter, clients_by_name: {}, schema_definition: lambda do |schema|
      schema_definition&.call(schema)
      schema.on_root_query_type do |t|
        t.field "echo", scalar_type_name do |f|
          f.argument "arg", scalar_type_name

          # `resolver` is overridden via our `test_adapter` above, but we still need to assign it to something here to
          # avoid errors from `elasticgraph-schema_definition`.
          f.resolver = :get_record_field_value
        end
      end
    end)

    @query = <<~QUERY
      query TestQuery($value: #{scalar_type_name}) {
        echo(arg: $value)
      }
    QUERY
  end

  def execute_query_with_variable_value(value)
    @test_resolver.return_value = nil
    @graphql.graphql_query_executor.execute(@query, variables: {value: value}).to_h
  end

  def execute_query_with_inline_query_value(value)
    @test_resolver.return_value = nil
    query = "query { echo#{ElasticGraph::Support::GraphQLFormatter.format_args(arg: value)} }"
    @graphql.graphql_query_executor.execute(query).to_h
  end

  def execute_query_returning(value)
    @test_resolver.return_value = value
    @graphql.graphql_query_executor.execute(@query).to_h
  end

  def expect_input_value_to_be_accepted(value, as: value, only_test_variable: false)
    response = execute_query_with_variable_value(value)

    expect(response).not_to include("errors")
    expect(response).to eq({"data" => {"echo" => nil}})
    expect(@test_resolver.last_arg_value).to eq(as)

    unless only_test_variable
      response = execute_query_with_inline_query_value(value)

      expect(response).not_to include("errors")
      expect(response).to eq({"data" => {"echo" => nil}})
      expect(@test_resolver.last_arg_value).to eq(as)
    end
  end

  # Use `define_method` instead of `def` to have access to `scalar_type_name`
  define_method :expect_input_value_to_be_rejected do |value, *error_snippets, expect_error_to_lack: [], only_test_variable: false|
    response = execute_query_with_variable_value(value)

    expect(response["data"]).to be nil
    expect(response.dig("errors", 0, "message")).to include(scalar_type_name)
    expect(response.dig("errors", 0, "extensions", "value")).to eq(value)

    explanation = response.dig("errors", 0, "extensions", "problems", 0, "explanation")
    if error_snippets.any?
      expect(explanation).to include(*error_snippets)
    end

    if expect_error_to_lack.any?
      expect(explanation).not_to include(*expect_error_to_lack)
    end

    unless only_test_variable
      response = execute_query_with_inline_query_value(value)

      message = response.dig("errors", 0, "message")
      expect(response["data"]).to be nil
      expect(message).to include(
        scalar_type_name,
        ElasticGraph::Support::GraphQLFormatter.serialize(value),
        *error_snippets
      )

      if expect_error_to_lack.any?
        expect(message).not_to include(*expect_error_to_lack)
      end
    end
  end

  def expect_result_to_be_returned(value, as: value)
    response = execute_query_returning(value)

    expect(response).to eq({"data" => {"echo" => as}})
  end

  def expect_result_to_be_replaced_with_nil(value)
    response = execute_query_returning(value)

    expect(response).to eq({"data" => {"echo" => nil}})
  end
end

class ScalarCoercionAdapterTestResolver
  attr_accessor :return_value, :last_arg_value

  def call(object, args, context)
    self.last_arg_value = args[:arg]
    return_value
  end
end
