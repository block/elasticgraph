# ElasticGraph::Support

This gem provides support utilities for the rest of the ElasticGraph gems. As
such, it is not intended to provide any public APIs for ElasticGraph users.

It includes JSON Schema validation functionality and other common utilities.

Importantly, it is intended to have as few dependencies as possible: it currently
only depends on `logger` (which originated in the Ruby standard library) and
`json_schemer` for JSON Schema validation.

## Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-support["elasticgraph-support"];
    class elasticgraph-support targetGemStyle;
    logger["logger"];
    elasticgraph-support --> logger;
    class logger externalGemStyle;
    json_schemer["json_schemer"];
    elasticgraph-support --> json_schemer;
    class json_schemer externalGemStyle;
    elasticgraph["elasticgraph"];
    elasticgraph --> elasticgraph-support;
    class elasticgraph otherEgGemStyle;
    elasticgraph-admin["elasticgraph-admin"];
    elasticgraph-admin --> elasticgraph-support;
    class elasticgraph-admin otherEgGemStyle;
    elasticgraph-apollo["elasticgraph-apollo"];
    elasticgraph-apollo --> elasticgraph-support;
    class elasticgraph-apollo otherEgGemStyle;
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    elasticgraph-datastore_core --> elasticgraph-support;
    class elasticgraph-datastore_core otherEgGemStyle;
    elasticgraph-elasticsearch["elasticgraph-elasticsearch"];
    elasticgraph-elasticsearch --> elasticgraph-support;
    class elasticgraph-elasticsearch otherEgGemStyle;
    elasticgraph-health_check["elasticgraph-health_check"];
    elasticgraph-health_check --> elasticgraph-support;
    class elasticgraph-health_check otherEgGemStyle;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-indexer --> elasticgraph-support;
    class elasticgraph-indexer otherEgGemStyle;
    elasticgraph-opensearch["elasticgraph-opensearch"];
    elasticgraph-opensearch --> elasticgraph-support;
    class elasticgraph-opensearch otherEgGemStyle;
    elasticgraph-query_registry["elasticgraph-query_registry"];
    elasticgraph-query_registry --> elasticgraph-support;
    class elasticgraph-query_registry otherEgGemStyle;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-schema_artifacts --> elasticgraph-support;
    class elasticgraph-schema_artifacts otherEgGemStyle;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-schema_definition --> elasticgraph-support;
    class elasticgraph-schema_definition otherEgGemStyle;
    elasticgraph-warehouse["elasticgraph-warehouse"];
    elasticgraph-warehouse --> elasticgraph-support;
    class elasticgraph-warehouse otherEgGemStyle;
    click logger href "https://rubygems.org/gems/logger" "Open on RubyGems.org" _blank;
    click json_schemer href "https://rubygems.org/gems/json_schemer" "Open on RubyGems.org" _blank;
```
