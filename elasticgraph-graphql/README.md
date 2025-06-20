# ElasticGraph::GraphQL

Provides the ElasticGraph GraphQL query engine.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-graphql["elasticgraph-graphql"];
    base64["base64"];
    elasticgraph-graphql --> base64;
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    elasticgraph-graphql --> elasticgraph-datastore_core;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-graphql --> elasticgraph-schema_artifacts;
    graphql["graphql"];
    elasticgraph-graphql --> graphql;
    graphql-c_parser["graphql-c_parser"];
    elasticgraph-graphql --> graphql-c_parser;
    elasticgraph-apollo["elasticgraph-apollo"];
    elasticgraph-apollo --> elasticgraph-graphql;
    elasticgraph-graphql_lambda["elasticgraph-graphql_lambda"];
    elasticgraph-graphql_lambda --> elasticgraph-graphql;
    elasticgraph-health_check["elasticgraph-health_check"];
    elasticgraph-health_check --> elasticgraph-graphql;
    elasticgraph-local["elasticgraph-local"];
    elasticgraph-local --> elasticgraph-graphql;
    elasticgraph-query_interceptor["elasticgraph-query_interceptor"];
    elasticgraph-query_interceptor --> elasticgraph-graphql;
    elasticgraph-query_registry["elasticgraph-query_registry"];
    elasticgraph-query_registry --> elasticgraph-graphql;
    elasticgraph-rack["elasticgraph-rack"];
    elasticgraph-rack --> elasticgraph-graphql;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-schema_definition --> elasticgraph-graphql;
    style elasticgraph-graphql fill:#lightblue,stroke:#2980b9,stroke-width:2px,color:#000;
    style base64 fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style elasticgraph-datastore_core fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-schema_artifacts fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style graphql fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style graphql-c_parser fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style elasticgraph-apollo fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-graphql_lambda fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-health_check fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-local fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-query_interceptor fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-query_registry fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-rack fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-schema_definition fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
```
