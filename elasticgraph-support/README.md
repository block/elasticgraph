# ElasticGraph::Support

This gem provides support utilities for the rest of the ElasticGraph gems. As
such, it is not intended to provide any public APIs for ElasticGraph users.

Importantly, it is intended to have as few dependencies as possible: it currently
only depends on `logger` (which originated in the Ruby standard library).

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-support["elasticgraph-support"];
    logger["logger"];
    elasticgraph-support --> logger;
    elasticgraph["elasticgraph"];
    elasticgraph --> elasticgraph-support;
    elasticgraph-admin["elasticgraph-admin"];
    elasticgraph-admin --> elasticgraph-support;
    elasticgraph-apollo["elasticgraph-apollo"];
    elasticgraph-apollo --> elasticgraph-support;
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    elasticgraph-datastore_core --> elasticgraph-support;
    elasticgraph-elasticsearch["elasticgraph-elasticsearch"];
    elasticgraph-elasticsearch --> elasticgraph-support;
    elasticgraph-health_check["elasticgraph-health_check"];
    elasticgraph-health_check --> elasticgraph-support;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-indexer --> elasticgraph-support;
    elasticgraph-json_schema["elasticgraph-json_schema"];
    elasticgraph-json_schema --> elasticgraph-support;
    elasticgraph-opensearch["elasticgraph-opensearch"];
    elasticgraph-opensearch --> elasticgraph-support;
    elasticgraph-query_registry["elasticgraph-query_registry"];
    elasticgraph-query_registry --> elasticgraph-support;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-schema_artifacts --> elasticgraph-support;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-schema_definition --> elasticgraph-support;
    style elasticgraph-support fill:#lightblue,stroke:#2980b9,stroke-width:2px,color:#000;
    style logger fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style elasticgraph fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-admin fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-apollo fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-datastore_core fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-elasticsearch fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-health_check fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-indexer fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-json_schema fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-opensearch fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-query_registry fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-schema_artifacts fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-schema_definition fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
```
