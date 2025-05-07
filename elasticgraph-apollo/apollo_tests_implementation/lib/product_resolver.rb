# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# The `apollo-federation-subgraph-compatibility` project requires that each tested
# implementation provide a `Query.product(id: ID!): Product` field. ElasticGraph provides
# `Query.products(...): ProductConnection!` automatically. To be able to pass the tests,
# we need to provide the `product` field, even though ElasticGraph doesn't natively provide
# it. This resolver supports that.
#
# @private
class ProductResolver
  def initialize(elasticgraph_graphql:, config:)
    @datastore_query_builder = elasticgraph_graphql.datastore_query_builder
    @product_index_def = elasticgraph_graphql.datastore_core.index_definitions_by_name.fetch("products")
    @datastore_router = elasticgraph_graphql.datastore_search_router
  end

  def resolve(field:, object:, args:, context:)
    query = @datastore_query_builder.new_query(
      search_index_definitions: [@product_index_def],
      monotonic_clock_deadline: context[:monotonic_clock_deadline],
      filters: [{"id" => {"equalToAnyOf" => [args.fetch("id")]}}],
      individual_docs_needed: true,
      request_all_fields: true
    )

    @datastore_router.msearch([query]).fetch(query).documents.first
  end
end
