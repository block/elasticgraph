# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin"
require "elastic_graph/graphql"
require "elastic_graph/indexer"
require "elastic_graph/graphiql"
require "elastic_graph/indexer/test_support/converters"

admin = ElasticGraph::Admin.from_yaml_file("config/settings.yaml")
graphql = ElasticGraph::GraphQL.from_yaml_file("config/settings.yaml")
indexer = ElasticGraph::Indexer.from_yaml_file("config/settings.yaml")

admin.cluster_configurator.configure_cluster($stdout)

# Example records expected by the apollo-federation-subgraph-compatibility test suite. based on:
# https://github.com/apollographql/apollo-federation-subgraph-compatibility/blob/2.1.0/COMPATIBILITY.md#expected-data-sets
dimension = {
  size: "small",
  weight: 1,
  unit: "kg"
}

user = {
  id: "1",
  averageProductsCreatedPerYear: 133,
  email: "support@apollographql.com",
  name: "Jane Smith",
  totalProductsCreated: 1337,
  yearsOfEmployment: 10
}

deprecated_product = {
  id: "1",
  sku: "apollo-federation-v1",
  package: "@apollo/federation-v1",
  reason: "Migrate to Federation V2",
  createdBy: user
}

products_research = [
  {
    id: "1",
    study: {
      caseNumber: "1234",
      description: "Federation Study"
    },
    outcome: nil
  },
  {
    id: "2",
    study: {
      caseNumber: "1235",
      description: "Studio Study"
    },
    outcome: nil
  }
]

products = [
  {
    id: "apollo-federation",
    sku: "federation",
    package: "@apollo/federation",
    variation: {
      id: "OSS"
    },
    dimensions: dimension,
    research: [products_research[0]],
    createdBy: user,
    notes: nil
  },
  {
    id: "apollo-studio",
    sku: "studio",
    package: "",
    variation: {
      id: "platform"
    },
    dimensions: dimension,
    research: [products_research[1]],
    createdBy: user,
    notes: nil
  }
]

inventory = {
  id: "apollo-oss",
  deprecatedProducts: [deprecated_product]
}

records_by_type = {
  "Product" => products,
  "DeprecatedProduct" => [deprecated_product],
  "ProductResearch" => products_research,
  "User" => [user],
  "Inventory" => [inventory]
}

events = records_by_type.flat_map do |type_name, records|
  records = records.map.with_index do |record, index|
    {
      __typename: type_name,
      __version: 1,
      __json_schema_version: 1
    }.merge(record)
  end

  ElasticGraph::Indexer::TestSupport::Converters.upsert_events_for_records(records)
end

indexer.processor.process(events, refresh_indices: true)

puts "Elasticsearch bootstrapping done. Booting the GraphQL server."

use Rack::ShowExceptions
run ElasticGraph::GraphiQL.new(graphql)
