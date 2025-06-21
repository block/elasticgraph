# ElasticGraph::Apollo

Implements the [Apollo Federation Subgraph Spec](https://www.apollographql.com/docs/federation/subgraph-spec/),
allowing an ElasticGraph application to be plugged into an Apollo-powered GraphQL server as a subgraph.

Note: this library only supports the v2 Federation specification.

## Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-apollo["elasticgraph-apollo"];
    class elasticgraph-apollo targetGemStyle;
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-apollo --> elasticgraph-graphql;
    class elasticgraph-graphql otherEgGemStyle;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-apollo --> elasticgraph-support;
    class elasticgraph-support otherEgGemStyle;
    graphql["graphql"];
    elasticgraph-apollo --> graphql;
    class graphql externalGemStyle;
    apollo-federation["apollo-federation"];
    elasticgraph-apollo --> apollo-federation;
    class apollo-federation externalGemStyle;
    click graphql href "https://rubygems.org/gems/graphql" "Open on RubyGems.org" _blank;
    click apollo-federation href "https://rubygems.org/gems/apollo-federation" "Open on RubyGems.org" _blank;
```

## Usage

First, add `elasticgraph-apollo` to your `Gemfile`:

``` ruby
gem "elasticgraph-apollo"
```

Finally, update your ElasticGraph schema artifact rake tasks in your `Rakefile`
so that `ElasticGraph::GraphQL::Apollo::SchemaDefinition::APIExtension` is
passed as one of the `extension_modules`:

``` ruby
require "elastic_graph/schema_definition/rake_tasks"
require "elastic_graph/apollo/schema_definition/api_extension"

ElasticGraph::SchemaDefinition::RakeTasks.new(
  schema_element_name_form: :snake_case,
  index_document_sizes: true,
  path_to_schema: "config/schema.rb",
  schema_artifacts_directory: artifacts_dir,
  extension_modules: [ElasticGraph::Apollo::SchemaDefinition::APIExtension]
)
```

That's it!

## Federation Version Support

This library supports multiple versions of Apollo federation. As of Jan. 2024, it supports:

* v2.0
* v2.3
* v2.5
* v2.6

By default, the newest version is targeted. If you need an older version (e.g. because your organization is
running an older Apollo version), you can configure it in your schema definition with:

```ruby
schema.target_apollo_federation_version "2.3"
```

## Testing Notes

This project uses https://github.com/apollographql/apollo-federation-subgraph-compatibility
to verify compatibility with Apollo. Things to note:

- Run `elasticgraph-apollo/script/test_compatibility` to run the compatibility tests (the CI build runs this).
- Run `elasticgraph-apollo/script/boot_eg_apollo_implementation` to boot the ElasticGraph compatibility test implementation (can be useful for debugging `test_compatibility` failures).
- These scripts require some additional dependencies to be installed (such as `docker`, `node`, and `npm`).
- To get that to pass locally on my Mac, I had to enable the `Use Docker Compose V2` flag in Docker Desktop (under "Preferences -> General").  Without that checked, I got errors like this:

```
ERROR: for apollo-federation-subgraph-compatibility_router_1  Cannot start service router: OCI runtime create failed: container_linux.go:380: starting container process caused: process_linux.go:545: container init caused: rootfs_linux.go:76: mounting "/host_mnt/Users/myron/Development/sq-elasticgraph-ruby/elasticgraph-apollo/vendor/apollo-federation-subgraph-compatibility/supergraph.graphql" to rootfs at "/etc/config/supergraph.graphql" caused: mount through procfd: not a directory: unknown: Are you trying to mount a directory onto a file (or vice-versa)? Check if the specified host path exists and is the expected type
```
