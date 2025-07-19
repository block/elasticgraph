# ElasticGraph::GraphiQL

Provides a GraphiQL IDE for ElasticGraph projects.

## Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-graphiql["elasticgraph-graphiql"];
    class elasticgraph-graphiql targetGemStyle;
    elasticgraph-rack["elasticgraph-rack"];
    elasticgraph-graphiql --> elasticgraph-rack;
    class elasticgraph-rack otherEgGemStyle;
    elasticgraph-local["elasticgraph-local"];
    elasticgraph-local --> elasticgraph-graphiql;
    class elasticgraph-local otherEgGemStyle;
```

## Usage

Use this gem with any rack-compatible server. Here's an example `config.ru`:

```ruby
require 'elastic_graph/graphql'
require 'elastic_graph/graphiql'

graphql = ElasticGraph::GraphQL.from_yaml_file("config/settings/local.yaml")
run ElasticGraph::GraphiQL.new(graphql)
```

Run this with `rackup` (after installing the `rackup` gem) or any other rack-compatible server.

## License

elasticgraph-graphiql is released under the [MIT License](https://opensource.org/licenses/MIT).

Part of the distributed code comes from the [GraphiQL project](https://github.com/graphql/graphiql),
also licensed under the MIT License, Copyright (c) GraphQL Contributors.
