# ElasticGraph::GraphQL

Provides the ElasticGraph GraphQL query engine.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-graphql --> base64;
    elasticgraph-graphql --> elasticgraph-datastore_core;
    elasticgraph-graphql --> elasticgraph-schema_artifacts;
    elasticgraph-graphql --> graphql;
    elasticgraph-graphql --> graphql-c_parser;
    elasticgraph-apollo --> elasticgraph-graphql;
    elasticgraph-graphql_lambda --> elasticgraph-graphql;
    elasticgraph-health_check --> elasticgraph-graphql;
    elasticgraph-local --> elasticgraph-graphql;
    elasticgraph-query_interceptor --> elasticgraph-graphql;
    elasticgraph-query_registry --> elasticgraph-graphql;
    elasticgraph-rack --> elasticgraph-graphql;
    elasticgraph-schema_definition --> elasticgraph-graphql;
    classDef currentGemStyle fill:#lightblue,stroke:#333,stroke-width:2px;
    classDef internalEgGemStyle fill:#lightgreen,stroke:#333,stroke-width:1px;
    classDef externalGemStyle fill:#lightcoral,stroke:#333,stroke-width:1px;
    classDef placeholderNodeStyle fill:#eee,stroke:#333,stroke-width:1px;
    class elasticgraph-graphql currentGemStyle;
    class base64 externalGemStyle;
    class elasticgraph-datastore_core internalEgGemStyle;
    class elasticgraph-schema_artifacts internalEgGemStyle;
    class graphql externalGemStyle;
    class graphql-c_parser externalGemStyle;
    class elasticgraph-apollo internalEgGemStyle;
    class elasticgraph-graphql_lambda internalEgGemStyle;
    class elasticgraph-health_check internalEgGemStyle;
    class elasticgraph-local internalEgGemStyle;
    class elasticgraph-query_interceptor internalEgGemStyle;
    class elasticgraph-query_registry internalEgGemStyle;
    class elasticgraph-rack internalEgGemStyle;
    class elasticgraph-schema_definition internalEgGemStyle;
```
