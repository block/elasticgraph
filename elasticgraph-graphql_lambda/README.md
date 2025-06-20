# ElasticGraph::GraphQLLambda

This gem wraps `elasticgraph-graphql` in order to run it from an AWS Lambda.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-graphql_lambda["elasticgraph-graphql_lambda"];
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-graphql_lambda --> elasticgraph-graphql;
    elasticgraph-lambda_support["elasticgraph-lambda_support"];
    elasticgraph-graphql_lambda --> elasticgraph-lambda_support;
    style elasticgraph-graphql_lambda fill:#lightblue,stroke:#2980b9,stroke-width:2px,color:#000;
    style elasticgraph-graphql fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-lambda_support fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
```
