# ElasticGraph::DatastoreCore

Contains the core datastore logic used by the rest of ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-datastore_core --> elasticgraph-schema_artifacts;
    elasticgraph-datastore_core --> elasticgraph-support;
    elasticgraph-admin --> elasticgraph-datastore_core;
    elasticgraph-graphql --> elasticgraph-datastore_core;
    elasticgraph-health_check --> elasticgraph-datastore_core;
    elasticgraph-indexer --> elasticgraph-datastore_core;
    elasticgraph-indexer_autoscaler_lambda --> elasticgraph-datastore_core;
    classDef currentGemStyle fill:#lightblue,stroke:#333,stroke-width:2px;
    classDef internalEgGemStyle fill:#lightgreen,stroke:#333,stroke-width:1px;
    classDef externalGemStyle fill:#lightcoral,stroke:#333,stroke-width:1px;
    classDef placeholderNodeStyle fill:#eee,stroke:#333,stroke-width:1px;
    class elasticgraph-datastore_core currentGemStyle;
    class elasticgraph-schema_artifacts internalEgGemStyle;
    class elasticgraph-support internalEgGemStyle;
    class elasticgraph-admin internalEgGemStyle;
    class elasticgraph-graphql internalEgGemStyle;
    class elasticgraph-health_check internalEgGemStyle;
    class elasticgraph-indexer internalEgGemStyle;
    class elasticgraph-indexer_autoscaler_lambda internalEgGemStyle;
```
