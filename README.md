# ElasticGraph

<p align="center">
  <a href="https://github.com/block/elasticgraph/actions/workflows/ci.yaml?query=branch%3Amain" alt="CI Status">
    <img alt="CI Status Badge" src="https://img.shields.io/github/actions/workflow/status/block/elasticgraph/ci.yaml?branch=main&label=CI%20Status"></a>
  <a href="https://github.com/block/elasticgraph/blob/main/spec_support/lib/elastic_graph/spec_support/enable_simplecov.rb" alt="ElasticGraph maintains 100% Test Coverage">
    <img alt="Test Coverage Badge" src="https://img.shields.io/badge/Test%20Coverage-100%25-green" /></a>
  <a href="https://github.com/block/elasticgraph/pulse" alt="Activity">
    <img alt="Activity Badge" src="https://img.shields.io/github/commit-activity/m/block/elasticgraph" /></a>
  <a href="https://github.com/block/elasticgraph/graphs/contributors" alt="GitHub Contributors">
    <img alt="Contributors Badge" src="https://img.shields.io/github/contributors/block/elasticgraph" /></a>
  <a href="https://rubygems.org/gems/elasticgraph" alt="RubyGems Release">
    <img alt="Gem Version Badge" src="https://img.shields.io/gem/v/elasticgraph" /></a>
  <a href="https://github.com/block/elasticgraph/blob/main/LICENSE.txt" alt="MIT License">
    <img alt="License Badge" src="https://img.shields.io/github/license/block/elasticgraph" /></a>
</p>

ElasticGraph is a general purpose, near real-time data query and search platform that is scalable and performant,
serves rich interactive queries, and dramatically simplifies the creation of complex reports. The platform combines
the power of indexing and search of Elasticsearch or OpenSearch with the query flexibility of GraphQL language.
Optimized for AWS cloud, it also offers scale and reliability.

ElasticGraph is a naturally flexible framework with many different possible applications. However, the main motivation we have for
building it is to power various data APIs, UIs and reports. These modern reports require filtering and aggregations across a body of ever
growing data sets. Modern APIs allow us to:

- Minimize network trips to retrieve your data
- Get exactly what you want in a single query. No over- or under-serving the data.
- Push filtering complex calculations to the backend.

## License

ElasticGraph is released under the [MIT License](https://opensource.org/licenses/MIT).

[Part of the distributed code](https://github.com/block/elasticgraph/blob/main/elasticgraph-rack/lib/elastic_graph/rack/graphiql/index.html)
comes from the [GraphiQL project](https://github.com/graphql/graphiql), also licensed under the
MIT License, Copyright (c) GraphQL Contributors.
