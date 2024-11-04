# ElasticGraph

<p align="center">
  <a href="https://github.com/block/elasticgraph/actions/workflows/ci.yaml?query=branch%3Amain" alt="CI Status">
    <img src="https://img.shields.io/github/check-runs/block/elasticgraph/main?label=CI%20Status" /></a>
  <a href="https://github.com/block/elasticgraph/blob/main/spec_support/lib/elastic_graph/spec_support/enable_simplecov.rb" alt="ElasticGraph maintains 100% Test Coverage">
    <img src="https://img.shields.io/badge/Test%20Coverage-100%25-green" /></a>
  <a href="https://github.com/block/elasticgraph/pulse" alt="Activity">
    <img src="https://img.shields.io/github/commit-activity/m/block/elasticgraph" /></a>
  <a href="https://github.com/block/elasticgraph/graphs/contributors" alt="GitHub Contributors">
    <img src="https://img.shields.io/github/contributors/block/elasticgraph" /></a>
  <a href="https://makeapullrequest.com" alt="PRs Welcome!">
    <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square" /></a>
  <a href="https://rubygems.org/gems/elasticgraph" alt="RubyGems Release">
    <img src="https://img.shields.io/gem/v/elasticgraph" /></a>
  <a href="https://github.com/block/elasticgraph/blob/main/LICENSE.txt" alt="MIT License">
    <img alt="MIT License" src="https://img.shields.io/github/license/block/elasticgraph" /></a>
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

## Libraries

ElasticGraph is designed to be modular, with a small core, and many built-in extensions that extend that core
for specific use cases. This minimizes exposure to vulnerabilities, reduces bloat, and makes ongoing upgrades
easier. The libraries that ship with ElasticGraph can be broken down into several categories.

### Core Libraries (8 gems)

These libraries form the core backbone of ElasticGraph that is designed to run in a production deployment. Every ElasticGraph deployment will need to use all of these.

* [elasticgraph](elasticgraph/README.md): ElasticGraph meta-gem that pulls in all the core ElasticGraph gems.
* [elasticgraph-admin](elasticgraph-admin/README.md): ElasticGraph gem that provides datastore administrative tasks, to keep a datastore up-to-date with an ElasticGraph schema.
* [elasticgraph-datastore_core](elasticgraph-datastore_core/README.md): ElasticGraph gem containing the core datastore support types and logic.
* [elasticgraph-graphql](elasticgraph-graphql/README.md): The ElasticGraph GraphQL query engine.
* [elasticgraph-indexer](elasticgraph-indexer/README.md): ElasticGraph gem that provides APIs to robustly index data into a datastore.
* [elasticgraph-json_schema](elasticgraph-json_schema/README.md): ElasticGraph gem that provides JSON Schema validation.
* [elasticgraph-schema_artifacts](elasticgraph-schema_artifacts/README.md): ElasticGraph gem containing code related to generated schema artifacts.
* [elasticgraph-support](elasticgraph-support/README.md): ElasticGraph gem providing support utilities to the other ElasticGraph gems.

#### Dependency Diagram

```mermaid
graph LR;
    elasticgraph --> elasticgraph-admin & elasticgraph-graphql & elasticgraph-indexer & elasticgraph-local
    elasticgraph-admin --> elasticgraph-datastore_core & elasticgraph-indexer & elasticgraph-schema_artifacts & elasticgraph-support & rake
    elasticgraph-datastore_core --> elasticgraph-schema_artifacts & elasticgraph-support
    elasticgraph-graphql --> elasticgraph-datastore_core & elasticgraph-schema_artifacts & graphql
    elasticgraph-indexer --> elasticgraph-datastore_core & elasticgraph-json_schema & elasticgraph-schema_artifacts & elasticgraph-support & hashdiff
    elasticgraph-json_schema --> elasticgraph-support & json_schemer
    elasticgraph-schema_artifacts --> elasticgraph-support
    elasticgraph-support --> logger
    style elasticgraph color: DodgerBlue;
    style elasticgraph-admin color: DodgerBlue;
    style elasticgraph-datastore_core color: DodgerBlue;
    style elasticgraph-graphql color: DodgerBlue;
    style elasticgraph-indexer color: DodgerBlue;
    style elasticgraph-json_schema color: DodgerBlue;
    style elasticgraph-schema_artifacts color: DodgerBlue;
    style elasticgraph-support color: DodgerBlue;
    style elasticgraph-local color: Green;
    style rake color: Red;
    style graphql color: Red;
    style hashdiff color: Red;
    style json_schemer color: Red;
    style logger color: Red;
click graphql href "https://rubygems.org/gems/graphql"
click hashdiff href "https://rubygems.org/gems/hashdiff"
click json_schemer href "https://rubygems.org/gems/json_schemer"
click logger href "https://rubygems.org/gems/logger"
click rake href "https://rubygems.org/gems/rake"
```

### AWS Lambda Integration Libraries (5 gems)

These libraries wrap the the core ElasticGraph libraries so that they can be deployed using AWS Lambda.

* [elasticgraph-admin_lambda](elasticgraph-admin_lambda/README.md): ElasticGraph gem that wraps elasticgraph-admin in an AWS Lambda.
* [elasticgraph-graphql_lambda](elasticgraph-graphql_lambda/README.md): ElasticGraph gem that wraps elasticgraph-graphql in an AWS Lambda.
* [elasticgraph-indexer_autoscaler_lambda](elasticgraph-indexer_autoscaler_lambda/README.md): ElasticGraph gem that monitors OpenSearch CPU utilization to autoscale indexer lambda concurrency.
* [elasticgraph-indexer_lambda](elasticgraph-indexer_lambda/README.md): Provides an AWS Lambda interface for an elasticgraph API
* [elasticgraph-lambda_support](elasticgraph-lambda_support/README.md): ElasticGraph gem that supports running ElasticGraph using AWS Lambda.

#### Dependency Diagram

```mermaid
graph LR;
    elasticgraph-admin_lambda --> rake & elasticgraph-admin & elasticgraph-lambda_support
    elasticgraph-graphql_lambda --> elasticgraph-graphql & elasticgraph-lambda_support
    elasticgraph-indexer_autoscaler_lambda --> elasticgraph-datastore_core & elasticgraph-lambda_support & aws-sdk-lambda & aws-sdk-sqs & ox
    elasticgraph-indexer_lambda --> elasticgraph-indexer & elasticgraph-lambda_support & aws-sdk-s3 & ox
    elasticgraph-lambda_support --> elasticgraph-opensearch & faraday_middleware-aws-sigv4
    style elasticgraph-admin_lambda color: DodgerBlue;
    style elasticgraph-graphql_lambda color: DodgerBlue;
    style elasticgraph-indexer_autoscaler_lambda color: DodgerBlue;
    style elasticgraph-indexer_lambda color: DodgerBlue;
    style elasticgraph-lambda_support color: DodgerBlue;
    style rake color: Red;
    style elasticgraph-admin color: Green;
    style elasticgraph-graphql color: Green;
    style elasticgraph-datastore_core color: Green;
    style aws-sdk-lambda color: Red;
    style aws-sdk-sqs color: Red;
    style ox color: Red;
    style elasticgraph-indexer color: Green;
    style aws-sdk-s3 color: Red;
    style elasticgraph-opensearch color: Green;
    style faraday_middleware-aws-sigv4 color: Red;
click aws-sdk-lambda href "https://rubygems.org/gems/aws-sdk-lambda"
click aws-sdk-s3 href "https://rubygems.org/gems/aws-sdk-s3"
click aws-sdk-sqs href "https://rubygems.org/gems/aws-sdk-sqs"
click faraday_middleware-aws-sigv4 href "https://rubygems.org/gems/faraday_middleware-aws-sigv4"
click ox href "https://rubygems.org/gems/ox"
click rake href "https://rubygems.org/gems/rake"
```

### Extensions (4 gems)

These libraries extend ElasticGraph to provide optional but commonly needed functionality.

* [elasticgraph-apollo](elasticgraph-apollo/README.md): An ElasticGraph extension that implements the Apollo federation spec.
* [elasticgraph-health_check](elasticgraph-health_check/README.md): An ElasticGraph extension that provides a health check for high availability deployments.
* [elasticgraph-query_interceptor](elasticgraph-query_interceptor/README.md): An ElasticGraph extension for intercepting datastore queries.
* [elasticgraph-query_registry](elasticgraph-query_registry/README.md): An ElasticGraph extension that supports safer schema evolution by limiting GraphQL queries based on a registry and validating registered queries against the schema.

#### Dependency Diagram

```mermaid
graph LR;
    elasticgraph-apollo --> elasticgraph-graphql & elasticgraph-support & graphql & apollo-federation
    elasticgraph-health_check --> elasticgraph-datastore_core & elasticgraph-graphql & elasticgraph-support
    elasticgraph-query_interceptor --> elasticgraph-graphql & elasticgraph-schema_artifacts
    elasticgraph-query_registry --> elasticgraph-graphql & elasticgraph-support & graphql & rake
    style elasticgraph-apollo color: DodgerBlue;
    style elasticgraph-health_check color: DodgerBlue;
    style elasticgraph-query_interceptor color: DodgerBlue;
    style elasticgraph-query_registry color: DodgerBlue;
    style elasticgraph-graphql color: Green;
    style elasticgraph-support color: Green;
    style graphql color: Red;
    style apollo-federation color: Red;
    style elasticgraph-datastore_core color: Green;
    style elasticgraph-schema_artifacts color: Green;
    style rake color: Red;
click apollo-federation href "https://rubygems.org/gems/apollo-federation"
click graphql href "https://rubygems.org/gems/graphql"
click rake href "https://rubygems.org/gems/rake"
```

### Datastore Adapters (2 gems)

These libraries adapt ElasticGraph to your choice of datastore (Elasticsearch or OpenSearch).

* [elasticgraph-elasticsearch](elasticgraph-elasticsearch/README.md): Wraps the Elasticsearch client for use by ElasticGraph.
* [elasticgraph-opensearch](elasticgraph-opensearch/README.md): Wraps the OpenSearch client for use by ElasticGraph.

#### Dependency Diagram

```mermaid
graph LR;
    elasticgraph-elasticsearch --> elasticgraph-support & elasticsearch & faraday & faraday-retry
    elasticgraph-opensearch --> elasticgraph-support & faraday & faraday-retry & opensearch-ruby
    style elasticgraph-elasticsearch color: DodgerBlue;
    style elasticgraph-opensearch color: DodgerBlue;
    style elasticgraph-support color: Green;
    style elasticsearch color: Red;
    style faraday color: Red;
    style faraday-retry color: Red;
    style opensearch-ruby color: Red;
click elasticsearch href "https://rubygems.org/gems/elasticsearch"
click faraday href "https://rubygems.org/gems/faraday"
click faraday-retry href "https://rubygems.org/gems/faraday-retry"
click opensearch-ruby href "https://rubygems.org/gems/opensearch-ruby"
```

### Local Development Libraries (3 gems)

These libraries are used for local development of ElasticGraph applications, but are not intended to be deployed to production (except for `elasticgraph-rack`).
`elasticgraph-rack` is used to boot ElasticGraph locally but can also be used to run ElasticGraph in any rack-compatible server (including a Rails application).

* [elasticgraph-local](elasticgraph-local/README.md): Provides support for developing and running ElasticGraph applications locally.
* [elasticgraph-rack](elasticgraph-rack/README.md): ElasticGraph gem for serving an ElasticGraph GraphQL endpoint using rack.
* [elasticgraph-schema_definition](elasticgraph-schema_definition/README.md): ElasticGraph gem that provides the schema definition API and generates schema artifacts.

#### Dependency Diagram

```mermaid
graph LR;
    elasticgraph-local --> elasticgraph-admin & elasticgraph-graphql & elasticgraph-indexer & elasticgraph-rack & elasticgraph-schema_definition & rackup & rake & webrick
    elasticgraph-rack --> elasticgraph-graphql & rack
    elasticgraph-schema_definition --> elasticgraph-graphql & elasticgraph-indexer & elasticgraph-json_schema & elasticgraph-schema_artifacts & elasticgraph-support & graphql & rake
    style elasticgraph-local color: DodgerBlue;
    style elasticgraph-rack color: DodgerBlue;
    style elasticgraph-schema_definition color: DodgerBlue;
    style elasticgraph-admin color: Green;
    style elasticgraph-graphql color: Green;
    style elasticgraph-indexer color: Green;
    style rackup color: Red;
    style rake color: Red;
    style webrick color: Red;
    style rack color: Red;
    style elasticgraph-json_schema color: Green;
    style elasticgraph-schema_artifacts color: Green;
    style elasticgraph-support color: Green;
    style graphql color: Red;
click graphql href "https://rubygems.org/gems/graphql"
click rack href "https://rubygems.org/gems/rack"
click rackup href "https://rubygems.org/gems/rackup"
click rake href "https://rubygems.org/gems/rake"
click webrick href "https://rubygems.org/gems/webrick"
```


## Versioning Policy

ElasticGraph does _not_ strictly follow the [SemVer](https://semver.org/) spec. We followed that early in the project's life
cycle and realized that it obscures some important compatibility information.

ElasticGraph's versioning policy is designed to communicate compatibility information related to the following stakeholders:

* **Application maintainers**: engineers that define an ElasticGraph schema, maintain project configuration, and perform upgrades.
* **Data publishers**: systems that publish data into an ElasticGraph application for ingestion by an ElasticGraph indexer.
* **GraphQL clients**: clients of the GraphQL API of an ElasticGraph application.

We use the following versioning scheme:

* Version numbers are in a `0.MAJOR.MINOR.PATCH` format. (The `0.` prefix is there in order to reserve `1.0.0` and all later versions
  for after ElasticGraph has been open-sourced).
* Increments to the PATCH version indicate that the new release contains no backwards incompatibilities for any stakeholders.
  It may contain bug fixes, new features, internal refactorings, and dependency upgrades, among other things. You can expect that
  PATCH level upgrades are always safe--just update the version in your bundle, generate new schema artifacts, and you should be done.
* Increments to the MINOR version indicate that the new release contains some backwards incompatibilities that may impact the
  **application maintainers** of some ElasticGraph applications. MINOR releases may include renames to configuration settings,
  changes to the schema definition API, and new schema definition requirements, among other things. You can expect that MINOR
  level upgrades can usually be done in 30 minutes or less (usually in a single commit!), with release notes and clear errors
  from ElasticGraph command line tasks providing guidance on how to upgrade.
* Increments to the MAJOR version indicate that the new release contains some backwards incompatibilities that may impact the
  **data publishers** or **GraphQL clients** of some ElasticGraph applications. MAJOR releases may include changes to the GraphQL
  schema that require careful migration of **GraphQL clients** or changes to how indexing is done that require a dataset to be
  re-indexed from scratch (e.g. by having **data publishers** republish their data into an ElasticGraph indexer running the new
  version). You can expect that the release notes will include detailed instructions on how to perform a MAJOR version upgrade.

Deprecation warnings may be included at any of these levels--for example, a PATCH release may contain a deprecation warning
for a breaking change that may impact **application maintainers** in an upcoming MINOR release, and a MINOR release may
contain deprecation warnings for breaking changes that may impact **data publishers** or **GraphQL clients** in an upcoming
MAJOR release.

Each version level is cumulative over the prior levels. That is, a MINOR release may include PATCH-level changes in addition
to backwards incompatibilities that may impact **application maintainers**. A MAJOR release may include PATCH-level or
MINOR-level changes in addition to backwards incompatibilities that may impact **data publishers** or **GraphQL clients**.

Note that this policy was first adopted in the `v0.15.1.0` release.  All prior releases aimed (with some occasional mistakes!)
to follow SemVer with a `0.MAJOR.MINOR.PATCH` versioning scheme.

Note that _all_ gems in this repository share the same version number. Every time we cut a release, we increment the version
for _all_ gems and release _all_ gems, even if a gem has had no changes since the last release. This is simpler to work with
than the alternatives.

## License

ElasticGraph is released under the [MIT License](https://opensource.org/licenses/MIT).

[Part of the distributed code](elasticgraph-rack/lib/elastic_graph/rack/graphiql/index.html)
comes from the [GraphiQL project](https://github.com/graphql/graphiql), also licensed under the
MIT License, Copyright (c) GraphQL Contributors.
