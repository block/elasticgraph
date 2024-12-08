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
