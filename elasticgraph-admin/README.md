# ElasticGraph::Admin

Provides datastore administrative tasks for ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-admin --> elasticgraph-datastore_core;
    elasticgraph-admin --> elasticgraph-indexer;
    elasticgraph-admin --> elasticgraph-schema_artifacts;
    elasticgraph-admin --> elasticgraph-support;
    elasticgraph-admin --> rake;
    elasticgraph-admin_lambda --> elasticgraph-admin;
    elasticgraph-local --> elasticgraph-admin;
    classDef currentGemStyle fill:#lightblue,stroke:#333,stroke-width:2px;
    classDef internalEgGemStyle fill:#lightgreen,stroke:#333,stroke-width:1px;
    classDef externalGemStyle fill:#lightcoral,stroke:#333,stroke-width:1px;
    classDef placeholderNodeStyle fill:#eee,stroke:#333,stroke-width:1px;
    class elasticgraph-admin currentGemStyle;
    class elasticgraph-datastore_core internalEgGemStyle;
    class elasticgraph-indexer internalEgGemStyle;
    class elasticgraph-schema_artifacts internalEgGemStyle;
    class elasticgraph-support internalEgGemStyle;
    class rake externalGemStyle;
    class elasticgraph-admin_lambda internalEgGemStyle;
    class elasticgraph-local internalEgGemStyle;
```
