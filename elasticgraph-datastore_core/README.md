# ElasticGraph::DatastoreCore

Contains the core datastore logic used by the rest of ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-datastore_core --> elasticgraph-schema_artifacts;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-datastore_core --> elasticgraph-support;
    elasticgraph-admin["elasticgraph-admin"];
    elasticgraph-admin --> elasticgraph-datastore_core;
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-graphql --> elasticgraph-datastore_core;
    elasticgraph-health_check["elasticgraph-health_check"];
    elasticgraph-health_check --> elasticgraph-datastore_core;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-indexer --> elasticgraph-datastore_core;
    elasticgraph-indexer_autoscaler_lambda["elasticgraph-indexer_autoscaler_lambda"];
    elasticgraph-indexer_autoscaler_lambda --> elasticgraph-datastore_core;
    style elasticgraph-datastore_core fill:#lightblue,stroke:#2980b9,stroke-width:2px,color:#000;
    style elasticgraph-schema_artifacts fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-support fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-admin fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-graphql fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-health_check fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-indexer fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-indexer_autoscaler_lambda fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
```
