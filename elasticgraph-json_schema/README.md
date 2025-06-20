# ElasticGraph::JSONSchema

Provides JSON Schema validation for ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    classDef currentGemStyle fill:#AED6F1,stroke:#3498DB,color:#000,stroke-width:2px;
    classDef internalEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#F4F6F7,stroke:#B3B6B7,color:#2980B9;
    elasticgraph-json_schema["elasticgraph-json_schema"];
    class elasticgraph-json_schema currentGemStyle;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-json_schema --> elasticgraph-support;
    class elasticgraph-support internalEgGemStyle;
    json_schemer["json_schemer"];
    elasticgraph-json_schema --> json_schemer;
    class json_schemer externalGemStyle;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-indexer --> elasticgraph-json_schema;
    class elasticgraph-indexer internalEgGemStyle;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-schema_definition --> elasticgraph-json_schema;
    class elasticgraph-schema_definition internalEgGemStyle;
    click json_schemer href "https://rubygems.org/gems/json_schemer" "Open on RubyGems.org" _blank;
```
