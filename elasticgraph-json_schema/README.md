# ElasticGraph::JSONSchema

Provides JSON Schema validation for ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-json_schema["elasticgraph-json_schema"];
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-json_schema --> elasticgraph-support;
    json_schemer["json_schemer"];
    elasticgraph-json_schema --> json_schemer;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-indexer --> elasticgraph-json_schema;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-schema_definition --> elasticgraph-json_schema;
    style elasticgraph-json_schema fill:#lightblue,stroke:#2980b9,stroke-width:2px,color:#000;
    style elasticgraph-support fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style json_schemer fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style elasticgraph-indexer fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-schema_definition fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
```
