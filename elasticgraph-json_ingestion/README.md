# ElasticGraph::JSONIngestion

Pluggable JSON Schema ingestion serializer for ElasticGraph.

This gem extracts the JSON Schema generation and validation logic from ElasticGraph's core into a
pluggable extension, following the same pattern as `elasticgraph-warehouse` and `elasticgraph-apollo`.
This is the first step toward supporting alternative ingestion serializers (e.g., Protocol Buffers).

Higher-level schema-definition entry points use the JSON Schema serializer by default for backward
compatibility, so existing users do not need configuration changes.

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
