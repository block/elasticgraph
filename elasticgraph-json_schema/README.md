# ElasticGraph::JSONSchema

Provides JSON Schema validation for ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-json_schema --> elasticgraph-support;
    elasticgraph-json_schema --> json_schemer;
    elasticgraph-indexer --> elasticgraph-json_schema;
    elasticgraph-schema_definition --> elasticgraph-json_schema;
    classDef currentGemStyle fill:#lightblue,stroke:#333,stroke-width:2px;
    classDef internalEgGemStyle fill:#lightgreen,stroke:#333,stroke-width:1px;
    classDef externalGemStyle fill:#lightcoral,stroke:#333,stroke-width:1px;
    classDef placeholderNodeStyle fill:#eee,stroke:#333,stroke-width:1px;
    class elasticgraph-json_schema currentGemStyle;
    class elasticgraph-support internalEgGemStyle;
    class json_schemer externalGemStyle;
    class elasticgraph-indexer internalEgGemStyle;
    class elasticgraph-schema_definition internalEgGemStyle;
```
