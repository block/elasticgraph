# ElasticGraph::Support

This gem provides support utilities for the rest of the ElasticGraph gems. As
such, it is not intended to provide any public APIs for ElasticGraph users.

Importantly, it is intended to have as few dependencies as possible: it currently
only depends on `logger` (which originated in the Ruby standard library).

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-support --> logger;
    elasticgraph --> elasticgraph-support;
    elasticgraph-admin --> elasticgraph-support;
    elasticgraph-apollo --> elasticgraph-support;
    elasticgraph-datastore_core --> elasticgraph-support;
    elasticgraph-elasticsearch --> elasticgraph-support;
    elasticgraph-health_check --> elasticgraph-support;
    elasticgraph-indexer --> elasticgraph-support;
    elasticgraph-json_schema --> elasticgraph-support;
    elasticgraph-opensearch --> elasticgraph-support;
    elasticgraph-query_registry --> elasticgraph-support;
    elasticgraph-schema_artifacts --> elasticgraph-support;
    elasticgraph-schema_definition --> elasticgraph-support;
    classDef currentGemStyle fill:#lightblue,stroke:#333,stroke-width:2px;
    classDef internalEgGemStyle fill:#lightgreen,stroke:#333,stroke-width:1px;
    classDef externalGemStyle fill:#lightcoral,stroke:#333,stroke-width:1px;
    classDef placeholderNodeStyle fill:#eee,stroke:#333,stroke-width:1px;
    class elasticgraph-support currentGemStyle;
    class logger externalGemStyle;
    class elasticgraph internalEgGemStyle;
    class elasticgraph-admin internalEgGemStyle;
    class elasticgraph-apollo internalEgGemStyle;
    class elasticgraph-datastore_core internalEgGemStyle;
    class elasticgraph-elasticsearch internalEgGemStyle;
    class elasticgraph-health_check internalEgGemStyle;
    class elasticgraph-indexer internalEgGemStyle;
    class elasticgraph-json_schema internalEgGemStyle;
    class elasticgraph-opensearch internalEgGemStyle;
    class elasticgraph-query_registry internalEgGemStyle;
    class elasticgraph-schema_artifacts internalEgGemStyle;
    class elasticgraph-schema_definition internalEgGemStyle;
```
