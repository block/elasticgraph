# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/graphql_formatter"

module GraphQLSupport
  def graphql_args(hash)
    ElasticGraph::Support::GraphQLFormatter.format_args(**hash)
  end

  def call_graphql_query(query, gql: graphql, allow_errors: false, **options)
    gql.graphql_query_executor.execute(query, **options).tap do |response|
      expect(response["errors"]).to(eq([]).or(eq(nil))) unless allow_errors
    end
  end

  def expect_error_related_to(response, *error_message_snippets)
    expect(response["errors"].size).to eq(1)
    expect(response["errors"].to_s).to include(*error_message_snippets)
    expect(response["data"]).to be nil
  end
end
