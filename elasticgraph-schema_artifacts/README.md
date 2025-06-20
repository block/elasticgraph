# ElasticGraph::SchemaArtifacts

Contains code related to ElasticGraph's generated schema artifacts.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-schema_artifacts --> elasticgraph-support;
    elasticgraph-admin --> elasticgraph-schema_artifacts;
    elasticgraph-datastore_core --> elasticgraph-schema_artifacts;
    elasticgraph-graphql --> elasticgraph-schema_artifacts;
    elasticgraph-indexer --> elasticgraph-schema_artifacts;
    elasticgraph-query_interceptor --> elasticgraph-schema_artifacts;
    elasticgraph-schema_definition --> elasticgraph-schema_artifacts;
    classDef currentGemStyle fill:#lightblue,stroke:#333,stroke-width:2px;
    classDef internalEgGemStyle fill:#lightgreen,stroke:#333,stroke-width:1px;
    classDef externalGemStyle fill:#lightcoral,stroke:#333,stroke-width:1px;
    classDef placeholderNodeStyle fill:#eee,stroke:#333,stroke-width:1px;
    class elasticgraph-schema_artifacts currentGemStyle;
    class elasticgraph-support internalEgGemStyle;
    class elasticgraph-admin internalEgGemStyle;
    class elasticgraph-datastore_core internalEgGemStyle;
    class elasticgraph-graphql internalEgGemStyle;
    class elasticgraph-indexer internalEgGemStyle;
    class elasticgraph-query_interceptor internalEgGemStyle;
    class elasticgraph-schema_definition internalEgGemStyle;
```
