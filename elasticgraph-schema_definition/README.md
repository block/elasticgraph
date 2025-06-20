# ElasticGraph::SchemaDefinition

Provides the ElasticGraph schema definition API, which is used to
generate ElasticGraph's schema artifacts.

This gem is not intended to be used in production--production should
just use the schema artifacts instead.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-schema_definition --> elasticgraph-graphql;
    elasticgraph-schema_definition --> elasticgraph-indexer;
    elasticgraph-schema_definition --> elasticgraph-json_schema;
    elasticgraph-schema_definition --> elasticgraph-schema_artifacts;
    elasticgraph-schema_definition --> elasticgraph-support;
    elasticgraph-schema_definition --> graphql;
    elasticgraph-schema_definition --> graphql-c_parser;
    elasticgraph-schema_definition --> rake;
    elasticgraph-local --> elasticgraph-schema_definition;
    classDef currentGemStyle fill:#lightblue,stroke:#333,stroke-width:2px;
    classDef internalEgGemStyle fill:#lightgreen,stroke:#333,stroke-width:1px;
    classDef externalGemStyle fill:#lightcoral,stroke:#333,stroke-width:1px;
    classDef placeholderNodeStyle fill:#eee,stroke:#333,stroke-width:1px;
    class elasticgraph-schema_definition currentGemStyle;
    class elasticgraph-graphql internalEgGemStyle;
    class elasticgraph-indexer internalEgGemStyle;
    class elasticgraph-json_schema internalEgGemStyle;
    class elasticgraph-schema_artifacts internalEgGemStyle;
    class elasticgraph-support internalEgGemStyle;
    class graphql externalGemStyle;
    class graphql-c_parser externalGemStyle;
    class rake externalGemStyle;
    class elasticgraph-local internalEgGemStyle;
```
