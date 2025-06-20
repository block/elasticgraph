# ElasticGraph::SchemaDefinition

Provides the ElasticGraph schema definition API, which is used to
generate ElasticGraph's schema artifacts.

This gem is not intended to be used in production--production should
just use the schema artifacts instead.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-schema_definition --> elasticgraph-graphql;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-schema_definition --> elasticgraph-indexer;
    elasticgraph-json_schema["elasticgraph-json_schema"];
    elasticgraph-schema_definition --> elasticgraph-json_schema;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-schema_definition --> elasticgraph-schema_artifacts;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-schema_definition --> elasticgraph-support;
    graphql["graphql"];
    elasticgraph-schema_definition --> graphql;
    graphql-c_parser["graphql-c_parser"];
    elasticgraph-schema_definition --> graphql-c_parser;
    rake["rake"];
    elasticgraph-schema_definition --> rake;
    elasticgraph-local["elasticgraph-local"];
    elasticgraph-local --> elasticgraph-schema_definition;
    style elasticgraph-schema_definition fill:#lightblue,stroke:#2980b9,stroke-width:2px,color:#000;
    style elasticgraph-graphql fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-indexer fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-json_schema fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-schema_artifacts fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-support fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style graphql fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style graphql-c_parser fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style rake fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style elasticgraph-local fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
```
