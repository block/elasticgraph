# ElasticGraph::Support

This gem provides support utilities for the rest of the ElasticGraph gems. As
such, it is not intended to provide any public APIs for ElasticGraph users.

Importantly, it is intended to have as few dependencies as possible: it currently
only depends on `logger` (which originated in the Ruby standard library).

## Dependency Diagram

```mermaid
graph LR;
    classDef currentGemStyle fill:#AED6F1,stroke:#3498DB,color:#000,stroke-width:2px;
    classDef internalEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#F4F6F7,stroke:#B3B6B7,color:#2980B9;
    elasticgraph-support["elasticgraph-support"];
    class elasticgraph-support currentGemStyle;
    logger["logger"];
    elasticgraph-support --> logger;
    class logger externalGemStyle;
    elasticgraph["elasticgraph"];
    elasticgraph --> elasticgraph-support;
    class elasticgraph internalEgGemStyle;
    elasticgraph-admin["elasticgraph-admin"];
    elasticgraph-admin --> elasticgraph-support;
    class elasticgraph-admin internalEgGemStyle;
    elasticgraph-apollo["elasticgraph-apollo"];
    elasticgraph-apollo --> elasticgraph-support;
    class elasticgraph-apollo internalEgGemStyle;
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    elasticgraph-datastore_core --> elasticgraph-support;
    class elasticgraph-datastore_core internalEgGemStyle;
    elasticgraph-elasticsearch["elasticgraph-elasticsearch"];
    elasticgraph-elasticsearch --> elasticgraph-support;
    class elasticgraph-elasticsearch internalEgGemStyle;
    elasticgraph-health_check["elasticgraph-health_check"];
    elasticgraph-health_check --> elasticgraph-support;
    class elasticgraph-health_check internalEgGemStyle;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-indexer --> elasticgraph-support;
    class elasticgraph-indexer internalEgGemStyle;
    elasticgraph-json_schema["elasticgraph-json_schema"];
    elasticgraph-json_schema --> elasticgraph-support;
    class elasticgraph-json_schema internalEgGemStyle;
    elasticgraph-opensearch["elasticgraph-opensearch"];
    elasticgraph-opensearch --> elasticgraph-support;
    class elasticgraph-opensearch internalEgGemStyle;
    elasticgraph-query_registry["elasticgraph-query_registry"];
    elasticgraph-query_registry --> elasticgraph-support;
    class elasticgraph-query_registry internalEgGemStyle;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-schema_artifacts --> elasticgraph-support;
    class elasticgraph-schema_artifacts internalEgGemStyle;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-schema_definition --> elasticgraph-support;
    class elasticgraph-schema_definition internalEgGemStyle;
    click logger href "https://rubygems.org/gems/logger" "Open on RubyGems.org" _blank;
```
