# ElasticGraph::LambdaSupport

This gem contains common lambda support logic that is used by all ElasticGraph
lambdas, such as lambda logging and OpenSearch connection support.

It is not meant to be used directly by end users of ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-lambda_support --> elasticgraph-opensearch;
    elasticgraph-lambda_support --> faraday_middleware-aws-sigv4;
    elasticgraph-admin_lambda --> elasticgraph-lambda_support;
    elasticgraph-graphql_lambda --> elasticgraph-lambda_support;
    elasticgraph-indexer_autoscaler_lambda --> elasticgraph-lambda_support;
    elasticgraph-indexer_lambda --> elasticgraph-lambda_support;
    classDef currentGemStyle fill:#lightblue,stroke:#333,stroke-width:2px;
    classDef internalEgGemStyle fill:#lightgreen,stroke:#333,stroke-width:1px;
    classDef externalGemStyle fill:#lightcoral,stroke:#333,stroke-width:1px;
    classDef placeholderNodeStyle fill:#eee,stroke:#333,stroke-width:1px;
    class elasticgraph-lambda_support currentGemStyle;
    class elasticgraph-opensearch internalEgGemStyle;
    class faraday_middleware-aws-sigv4 externalGemStyle;
    class elasticgraph-admin_lambda internalEgGemStyle;
    class elasticgraph-graphql_lambda internalEgGemStyle;
    class elasticgraph-indexer_autoscaler_lambda internalEgGemStyle;
    class elasticgraph-indexer_lambda internalEgGemStyle;
```
