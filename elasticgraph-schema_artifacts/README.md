# ElasticGraph::SchemaArtifacts

Contains code related to ElasticGraph's generated schema artifacts.

## Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    class elasticgraph-schema_artifacts targetGemStyle;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-schema_artifacts --> elasticgraph-support;
    class elasticgraph-support otherEgGemStyle;
    elasticgraph-admin["elasticgraph-admin"];
    elasticgraph-admin --> elasticgraph-schema_artifacts;
    class elasticgraph-admin otherEgGemStyle;
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    elasticgraph-datastore_core --> elasticgraph-schema_artifacts;
    class elasticgraph-datastore_core otherEgGemStyle;
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-graphql --> elasticgraph-schema_artifacts;
    class elasticgraph-graphql otherEgGemStyle;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-indexer --> elasticgraph-schema_artifacts;
    class elasticgraph-indexer otherEgGemStyle;
    elasticgraph-query_interceptor["elasticgraph-query_interceptor"];
    elasticgraph-query_interceptor --> elasticgraph-schema_artifacts;
    class elasticgraph-query_interceptor otherEgGemStyle;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-schema_definition --> elasticgraph-schema_artifacts;
    class elasticgraph-schema_definition otherEgGemStyle;
```
