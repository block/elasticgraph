# ElasticGraph::LambdaSupport

This gem contains common lambda support logic that is used by all ElasticGraph
lambdas, such as lambda logging and OpenSearch connection support.

It is not meant to be used directly by end users of ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-lambda_support["elasticgraph-lambda_support"];
    elasticgraph-opensearch["elasticgraph-opensearch"];
    elasticgraph-lambda_support --> elasticgraph-opensearch;
    faraday_middleware-aws-sigv4["faraday_middleware-aws-sigv4"];
    elasticgraph-lambda_support --> faraday_middleware-aws-sigv4;
    elasticgraph-admin_lambda["elasticgraph-admin_lambda"];
    elasticgraph-admin_lambda --> elasticgraph-lambda_support;
    elasticgraph-graphql_lambda["elasticgraph-graphql_lambda"];
    elasticgraph-graphql_lambda --> elasticgraph-lambda_support;
    elasticgraph-indexer_autoscaler_lambda["elasticgraph-indexer_autoscaler_lambda"];
    elasticgraph-indexer_autoscaler_lambda --> elasticgraph-lambda_support;
    elasticgraph-indexer_lambda["elasticgraph-indexer_lambda"];
    elasticgraph-indexer_lambda --> elasticgraph-lambda_support;
    style elasticgraph-lambda_support fill:#lightblue,stroke:#2980b9,stroke-width:2px,color:#000;
    style elasticgraph-opensearch fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style faraday_middleware-aws-sigv4 fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style elasticgraph-admin_lambda fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-graphql_lambda fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-indexer_autoscaler_lambda fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticgraph-indexer_lambda fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
```
