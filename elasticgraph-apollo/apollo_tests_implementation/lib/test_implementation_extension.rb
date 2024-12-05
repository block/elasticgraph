# Copyright 2024 Block, Inc.
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
# it.
#
# This defines an extension that injects a custom resolver that supports the field.
# @private
module ApolloTestImplementationExtension
  def graphql_resolvers
    @graphql_resolvers ||= [product_field_resolver] + super
  end

  def product_field_resolver
    @product_field_resolver ||= ProductFieldResolver.new(
      datastore_query_builder: datastore_query_builder,
      product_index_def: datastore_core.index_definitions_by_name.fetch("products"),
      datastore_router: datastore_search_router
    )
  end

  # @private
  class ProductFieldResolver
    def initialize(datastore_query_builder:, product_index_def:, datastore_router:)
      @datastore_query_builder = datastore_query_builder
      @product_index_def = product_index_def
      @datastore_router = datastore_router
    end

    def can_resolve?(field:, object:)
      field.parent_type.name == :Query && field.name == :product
    end

    def resolve(field:, object:, args:, context:, lookahead:)
      query = @datastore_query_builder.new_query(
        search_index_definitions: [@product_index_def],
        monotonic_clock_deadline: context[:monotonic_clock_deadline],
        filter: {"id" => {"equalToAnyOf" => [args.fetch("id")]}},
        individual_docs_needed: true,
        requested_fields: %w[
          id sku package notes
          variation.id
          dimensions.size dimensions.weight dimensions.unit
          createdBy.averageProductsCreatedPerYear createdBy.email createdBy.name createdBy.totalProductsCreated createdBy.yearsOfEmployment
          research.study.caseNumber research.study.description research.outcome
        ]
      )

      @datastore_router.msearch([query]).fetch(query).documents.first
    end
  end
end