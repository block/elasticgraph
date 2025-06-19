<a href="https://block.github.io/elasticgraph/">
  <img src="https://raw.githubusercontent.com/block/elasticgraph/main/config/site/src/assets/images/logo-and-name.png" alt="ElasticGraph logo" width="450" />
</a>

<p>
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

[ElasticGraph](https://block.github.io/elasticgraph/) provides schema-driven, scalable, cloud-native,
batteries-included GraphQL with superpowers, backed by Elasticsearch / OpenSearch.

## Try ElasticGraph in 1 Minute

Boot an example ElasticGraph project locally with:

```bash
curl -s https://block.github.io/elasticgraph/dc.yml | docker compose -f - up --pull always
```

Then visit the [local GraphiQL UI](http://localhost:9000/) to try some [example queries](https://block.github.io/elasticgraph/query-api/overview/).

## Start a New Project in 5 Minutes

Bootstrap a new ElasticGraph project with:

```bash
gem exec elasticgraph new path/to/project
cd path/to/project
bundle exec rake boot_locally
```

The project website has a full [getting started guide](https://block.github.io/elasticgraph/getting-started/).

## Architecture

ElasticGraph is designed as a modular system with a small core and numerous built-in extensions.
The codebase is a monorepo containing multiple Ruby gems that work together to provide a rich, comprehensive data platform.

For a detailed exploration of the system architecture, component gems, and their interactions,
please see the [CODEBASE_OVERVIEW.md](https://github.com/block/elasticgraph/blob/main/CODEBASE_OVERVIEW.md).

## Documentation

The [project website](https://block.github.io/elasticgraph/) has extensive user guides and documentation.

## Contributing

We welcome contributions to ElasticGraph!

* Join the community on [Discord](https://discord.gg/8m9FqJ7a7F).
* Read [CONTRIBUTING.md](https://github.com/block/elasticgraph/blob/main/CONTRIBUTING.md) to learn how you can help, including our development workflow and coding conventions.

## License

ElasticGraph is released under the [MIT License](https://github.com/block/elasticgraph/blob/main/LICENSE.txt).

The [GraphiQL interface](https://github.com/block/elasticgraph/blob/main/elasticgraph-rack/lib/elastic_graph/rack/graphiql/index.html)
bundled with `elasticgraph-rack` is derived from the [GraphiQL project](https://github.com/graphql/graphiql), which is also licensed
under the MIT License, Copyright (c) GraphQL Contributors.
