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
    style elasticgraph-lambda_support color:DodgerBlue,stroke-width:2px,stroke:DodgerBlue;
    style elasticgraph-opensearch color:Green,stroke:Green;
    style faraday_middleware-aws-sigv4 color:Red,stroke:Red;
    style elasticgraph-admin_lambda color:Green,stroke:Green;
    style elasticgraph-graphql_lambda color:Green,stroke:Green;
    style elasticgraph-indexer_autoscaler_lambda color:Green,stroke:Green;
    style elasticgraph-indexer_lambda color:Green,stroke:Green;
    click faraday_middleware-aws-sigv4 href "https://rubygems.org/gems/faraday_middleware-aws-sigv4" "Open on RubyGems.org" _blank;
```
