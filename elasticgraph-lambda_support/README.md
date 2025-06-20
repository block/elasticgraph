# ElasticGraph::LambdaSupport

This gem contains common lambda support logic that is used by all ElasticGraph
lambdas, such as lambda logging and OpenSearch connection support.

It is not meant to be used directly by end users of ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    classDef currentGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef internalEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-lambda_support["elasticgraph-lambda_support"];
    class elasticgraph-lambda_support currentGemStyle;
    elasticgraph-opensearch["elasticgraph-opensearch"];
    elasticgraph-lambda_support --> elasticgraph-opensearch;
    class elasticgraph-opensearch internalEgGemStyle;
    faraday_middleware-aws-sigv4["faraday_middleware-aws-sigv4"];
    elasticgraph-lambda_support --> faraday_middleware-aws-sigv4;
    class faraday_middleware-aws-sigv4 externalGemStyle;
    elasticgraph-admin_lambda["elasticgraph-admin_lambda"];
    elasticgraph-admin_lambda --> elasticgraph-lambda_support;
    class elasticgraph-admin_lambda internalEgGemStyle;
    elasticgraph-graphql_lambda["elasticgraph-graphql_lambda"];
    elasticgraph-graphql_lambda --> elasticgraph-lambda_support;
    class elasticgraph-graphql_lambda internalEgGemStyle;
    elasticgraph-indexer_autoscaler_lambda["elasticgraph-indexer_autoscaler_lambda"];
    elasticgraph-indexer_autoscaler_lambda --> elasticgraph-lambda_support;
    class elasticgraph-indexer_autoscaler_lambda internalEgGemStyle;
    elasticgraph-indexer_lambda["elasticgraph-indexer_lambda"];
    elasticgraph-indexer_lambda --> elasticgraph-lambda_support;
    class elasticgraph-indexer_lambda internalEgGemStyle;
    click faraday_middleware-aws-sigv4 href "https://rubygems.org/gems/faraday_middleware-aws-sigv4" "Open on RubyGems.org" _blank;
```
