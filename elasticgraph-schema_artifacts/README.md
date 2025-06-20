# ElasticGraph::SchemaArtifacts

Contains code related to ElasticGraph's generated schema artifacts.

## Dependency Diagram

```mermaid
graph LR;
    classDef currentGemStyle fill:#AED6F1,stroke:#3498DB,color:#000,stroke-width:2px;
    classDef internalEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#FADBD8,stroke:#EC7063,color:#2980B9;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    class elasticgraph-schema_artifacts currentGemStyle;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-schema_artifacts --> elasticgraph-support;
    class elasticgraph-support internalEgGemStyle;
    elasticgraph-admin["elasticgraph-admin"];
    elasticgraph-admin --> elasticgraph-schema_artifacts;
    class elasticgraph-admin internalEgGemStyle;
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    elasticgraph-datastore_core --> elasticgraph-schema_artifacts;
    class elasticgraph-datastore_core internalEgGemStyle;
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-graphql --> elasticgraph-schema_artifacts;
    class elasticgraph-graphql internalEgGemStyle;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-indexer --> elasticgraph-schema_artifacts;
    class elasticgraph-indexer internalEgGemStyle;
    elasticgraph-query_interceptor["elasticgraph-query_interceptor"];
    elasticgraph-query_interceptor --> elasticgraph-schema_artifacts;
    class elasticgraph-query_interceptor internalEgGemStyle;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-schema_definition --> elasticgraph-schema_artifacts;
    class elasticgraph-schema_definition internalEgGemStyle;
```
