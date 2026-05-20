# ElasticGraph::JSONIngestion

JSON Schema ingestion support for ElasticGraph.

This gem contains the JSON Schema helper code used by schema definition to generate indexing
event schemas and merge ElasticGraph metadata into versioned schema artifacts.

## Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-json_ingestion["elasticgraph-json_ingestion"];
    class elasticgraph-json_ingestion targetGemStyle;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-json_ingestion --> elasticgraph-support;
    class elasticgraph-support otherEgGemStyle;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-schema_definition --> elasticgraph-json_ingestion;
    class elasticgraph-schema_definition otherEgGemStyle;
```
