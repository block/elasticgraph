# ElasticGraph::QueryRegistry

`ElasticGraph::QueryRegistry` provides a simple source-controlled query
registry for ElasticGraph applications. This is designed for cases where
the clients of your application are other internal teams in your organization,
who are willing to register their queries before using them.

Query registration provides a few key benefits:

* It gives you as the application owner the chance to vet queries and
  give feedback to your clients. Queries may not initially be written
  in the most optimal way (e.g. leveraging your sharding strategy), so
  the review process gives you a chance to provide feedback.
* It allows you to provide stronger guarantees around schema changes.
  Tooling is included that will validate each and every registered query
  against your schema as part of your CI build, allowing you to quickly
  iterate on your schema without needing to check if you'll break clients.
* It allows you to control the data clients have access to. When
  a client attempts to register a query accessing fields they aren't
  allowed to, you can choose not to approve the query. Once setup and
  configured, this library will block clients from submitting queries
  that have not been registered.
* Your GraphQL endpoint will be a bit more efficient. Parsing large
  GraphQL queries can be a bit slow (in our testing, a 10 KB query
  string takes about ~10ms to parse), and the registry will cache and
  reuse the parsed form of registered queries.

Importantly, once installed, registered clients who send unregistered
queries will get errors. Unregistered clients can similarly be blocked
if desired based on a configuration setting.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-query_registry --> elasticgraph-graphql;
    elasticgraph-query_registry --> elasticgraph-support;
    elasticgraph-query_registry --> graphql;
    elasticgraph-query_registry --> graphql-c_parser;
    elasticgraph-query_registry --> rake;
    no_eg_dependents[(No direct EG dependents)] --> elasticgraph-query_registry;
    classDef currentGemStyle fill:#lightblue,stroke:#333,stroke-width:2px;
    classDef internalEgGemStyle fill:#lightgreen,stroke:#333,stroke-width:1px;
    classDef externalGemStyle fill:#lightcoral,stroke:#333,stroke-width:1px;
    classDef placeholderNodeStyle fill:#eee,stroke:#333,stroke-width:1px;
    class elasticgraph-query_registry currentGemStyle;
    class elasticgraph-graphql internalEgGemStyle;
    class elasticgraph-support internalEgGemStyle;
    class graphql externalGemStyle;
    class graphql-c_parser externalGemStyle;
    class rake externalGemStyle;
    class no_eg_dependents placeholderNodeStyle;
```

## Query Verification Guarantees

The query verification provided by this library is limited in scope. It
only checks to see if the queries and schema are compatible (in the sense
that the ElasticGraph endpoint will be able to successfully respond to
the queries). It does _not_ give any guarantee that a schema change is
100% safe for clients. For example, if you change a non-null field to be
nullable, it has no impact on ElasticGraph's ability to respond to a query
(and the verification performed by this library will allow it), but it may
break the client (e.g. if the client's usage of the response assumes
non-null field values).

When changing the GraphQL schema of an ElasticGraph application, you
will still need to consider how it may impact clients, but you won't
need to worry about ElasticGraph beginning to return errors to any
existing queries.

## Directory Structure

This library uses a directory as the registry. Conventionally, this
would go in `config/queries` but it can really go anywhere. The directory
structure will look like this:

```
config
└── queries
    ├── client1
    │   ├── query1.graphql
    │   └── query2.graphql
    ├── client2
    └── client3
        └── query1.graphql
```

Within the registry directory, there is a subdirectory for each
registered client. Each client directory contains that client's
registered queries as a set of `*.graphql` files (the extension is
required). Note that a client can be registered with no
associated queries (such as `client2`, above). This can be important
when you have configured `allow_unregistered_clients: true`. With
this setup, `client2` will not be able to submit any queries, but
a completely unregistered client (say, `client4`) will be able to
execute any query.

## Setup

First, add `elasticgraph-query_registry` to your `Gemfile`:

``` ruby
gem "elasticgraph-query_registry"
```

Next, configure this library in your ElasticGraph config YAML files:

``` yaml
graphql:
  extension_modules:
  - require_path: elastic_graph/query_registry/graphql_extension
    name: ElasticGraph::QueryRegistry::GraphQLExtension
query_registry:
  allow_unregistered_clients: false
  allow_any_query_for_clients:
  - adhoc_client
  path_to_registry: config/queries
```

Next, load the `ElasticGraph::QueryRegistry` rake tasks in your `Rakefile`:

``` ruby
require "elastic_graph/query_registry/rake_tasks"

ElasticGraph::QueryRegistry::RakeTasks.from_yaml_file(
  "path/to/settings.yaml",
  "config/queries",
  require_eg_latency_slo_directive: true
)
```

You'll want to add `rake query_registry:validate_queries` to your CI build so
that every registered query is validated as part of every build.

Finally, your application needs to include a `client:` when submitting
each GraphQL query for execution. The client `name` should match the
name of one of the registry client subdirectories. If you are using
`elasticgraph-lambda`, note that it does this automatically, but you may
need to configure `aws_arn_client_name_extraction_regex` so that it is
able to extract the `client_name` from the IAM ARN correctly.

Important note: if your application fails to identify clients properly,
and `allow_unregistered_clients` is set to `true`, then _all_ clients
will be allowed to execute _all_ queries! We recommend you set
`allow_unregistered_clients` to `false` unless you specifically need
to allow unregistered clients. For specific clients that need to be
allowed to run any query, you can list them in `allow_any_query_for_clients`.

## Workflow

This library also uses some generated artifacts (`*.variables.yaml` files)
so it can detect when a change to the structure or type of a variable is
backward-incompatible. For this to work, it requires that the generated
variables files are kept up-to-date. Any time a change impacts the structure
of any variables used by any queries, you'll need to run a task like
`query_registry:dump_variables[client_name, query_name]` (or
`query_registry:dump_variables:all`) to update the artifacts.

Don't worry about if you forget this, though--the
`query_registry:validate_queries` task will also fail and give you
instructions anytime a variables file is not up-to-date.
