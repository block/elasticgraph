---
layout: markdown
title: Guiding Principles
permalink: /guides/guiding-principles/
nav_title: Guiding Principles
menu_order: 40
---

These are the "north stars" that guide ElasticGraph development. They guide the decisions and tradeoffs we make.

### General Principles

**ElasticGraph is designed to be modular with minimal dependencies.**
: We're cautious about taking on new dependencies: we'll only add a new one when the functionality it offers
  goes far beyond what we can quickly and easily write ourselves. Combined with the modular nature of ElasticGraph,
  this supports slim deployment artifacts that enable AWS Lambda deployments to maintain minimal boot
  times. For example, an `elasticgraph-indexer` deployment has no dependency on the `graphql` gem.

**ElasticGraph is designed to be highly extensible.**
: While the "core" of ElasticGraph is intended to support most common needs, we know it can't
  meet every need. Instead, it includes an extension system and ships with a number of built-in
  extensions, including [elasticgraph-apollo](https://github.com/block/elasticgraph/tree/main/elasticgraph-apollo),
  [elasticgraph-health_check](https://github.com/block/elasticgraph/tree/main/elasticgraph-health_check),
  [elasticgraph-query_interceptor](https://github.com/block/elasticgraph/tree/main/elasticgraph-query_interceptor),
  [elasticgraph-query_registry](https://github.com/block/elasticgraph/tree/main/elasticgraph-query_registry),
  and the various [AWS lambda components](https://github.com/block/elasticgraph/blob/main/CODEBASE_OVERVIEW.md#aws-lambda-integration-libraries-5-gems).
  In addition, extensions are designed to apply hermetically: when applied to one instance of `ElasticGraph::GraphQL`, `ElasticGraph::Indexer`,
  or `ElasticGraph::SchemaDefinition::API`, they don't apply to any other instances of those classes.

### Query API Principles

**We aim to maximize query functionality while minimizing the API surface area.**
: This allows users to learn fewer concepts and apply them to more situations.
  For example, we don't provide a specific API to lookup documents by `id`--instead
  the filtering API (which can be used to search on any field) can be used to search
  on ids.

**Query validity must be statically verifiable by the GraphQL schema.**
: The GraphQL static type system is powerful. We want to leverage that so that clients
  can trust that a query that satisfies the schema is guaranteed to work at runtime. That
  sometimes limits what Elasticsearch/OpenSearch features we are able to expose because
  some combinations of features result in runtime errors from the datastore. For example,
  sub-aggregation pagination is not supported because using a [composite aggregation](https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-composite-aggregation.html)
  as a sub-aggregation of a composite aggregation results in a runtime exception from
  Elasticsearch/OpenSearch.

### Indexing Principles

**The indexing pipeline must deterministically converge on the indexed state, regardless of duplicate and out-of-order events.**
: This design offers some key benefits:
 * It makes maintenance easier. For example, it's _always_ safe to retry ingesting failed indexing events. You don't have to worry
   that the data in your index might "regress" to a prior state.
 * It makes it easy to operate multiple ElasticGraph instances (e.g. each in a different AWS region) which are guaranteed to
   converge on the same indexed state. (This is how we recommend deploying ElasticGraph for projects that require high availability.)
 * It allows you to recover from a [red OpenSearch or Elasticsearch cluster](https://www.elastic.co/guide/en/elasticsearch/reference/current/red-yellow-cluster-status.html#fix-cluster-status-recover-nodes)
   by restoring from a snapshot and playing back the indexing events after the snapshot was taken--this is guaranteed to converge
   on the indexed state you started with.

### Schema Principles

**The impact of schema changes must be statically visible and easy to reason about.**
: Source-controlled [schema artifacts]({% link guides/how-it-works.md %}) indicate exactly
  which stakeholders are impacted by a schema change. For example, a schema change that
  updates `schema.graphql` but not `json_schemas.yaml` will impact GraphQL clients but not
  data publishers. This simplifies code review of ElasticGraph projects because the impact
  of a schema change is clearly indicated by the diff of the schema artifacts.

**We aim to provide friendly, actionable errors whenever a schema definition is invalid.**
: If a schema definition produces schema artifacts, those schema artifacts will be valid and work
  at runtime. If valid schema artifacts cannot be produced, ElasticGraph will provide errors
  that clearly indicate what's wrong and how to proceed.

**The schema must be safely evolvable without requiring coordinated deploys with data publishers.**
: The GraphQL type system is designed for continuous evolution of the API exposed to clients.
  ElasticGraph augments this by supporting safe continuous evolution of the indexing schema.
  JSON schema artifacts are versioned which allows an `elasticgraph-indexer` and a data publisher
  to be deployed independently with no interruption to the indexing pipeline.

**Schema definition features which apply to multiple types of schema elements must use the same API everywhere.**
: For example, documentation can be added to any type of schema element (a type, field, argument, enum value, etc)
  using the same API (`element.documentation "Description"`). This is achieved through a set of
  [mixins](https://github.com/block/elasticgraph/tree/main/elasticgraph-schema_definition/lib/elastic_graph/schema_definition/mixins).

### Codebase Principles

**We aim for consistency.**
: We try to use terminology in a consistent manner throughout the codebase. Our APIs are designed to
  use a consistent style and "voice" so that they are predictable to use.

**The codebase has no global state.**
: Global state is quite common in a lot of Ruby codebases (it's very convenient to expose something
  like database connection as a via a class attribute) but we avoid that throughout the codebase. Instead,
  our entry points like `ElasticGraph::GraphQL` and `ElasticGraph::Indexer` inject dependencies into each
  component. This makes ElasticGraph easier to reason about, aids in making ElasticGraph threadsafe,
  and supports the ability to have multiple application instances in the same Ruby process.

**We favor an immutable functional style.**
: Where feasible, we create immutable objects and write functional code that transforms those objects.
  This makes the codebase easier to reason about and maintain.

**When facing two ways to implement a given piece of functionality, we prefer the simpler approach.**
: Simpler code and architectures makes for easier debugging later, and allows new contributors to more quickly
  onboard and contribute to the project.

**We avoid monkey patching.**
: While monkey-patching is a common technique in the Ruby community, it often leads to future problems and
  we avoid it.

**Every line and branch of code must be covered by tests except where we intentionally opt-out.**
: Our CI build enforces 100% test coverage except where we opt-out using [`:nocov:` comments](https://github.com/search?q=repo%3Ablock%2Felasticgraph%20nocov&type=code).
  This high level of test coverage means that most of the time, if it passes the CI build, it works in production.
  It also makes it obvious at a glance which lines of code are uncovered by tests--if a line isn't wrapped with a
  `:nocov:` comment then you know it's covered!

**We aim to validate all snippets and code examples at this website.**
: Our documentation is so much more useful if users can trust that the code snippets we provide always work.
  When a change to the codebase breaks an example from the website, we want to be notified about it so that
  we can fix it. The CI build includes full validation of website code snippets.
