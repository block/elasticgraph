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
    style elasticgraph-datastore_core color:DodgerBlue,stroke-width:2px,stroke:DodgerBlue;
    style elasticgraph-schema_artifacts color:Green,stroke:Green;
    style elasticgraph-support color:Green,stroke:Green;
    style elasticgraph-admin color:Green,stroke:Green;
    style elasticgraph-graphql color:Green,stroke:Green;
    style elasticgraph-health_check color:Green,stroke:Green;
    style elasticgraph-indexer color:Green,stroke:Green;
    style elasticgraph-indexer_autoscaler_lambda color:Green,stroke:Green;
```
