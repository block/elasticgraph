# ElasticGraph::GraphQLLambda

This gem wraps `elasticgraph-graphql` in order to run it from an AWS Lambda.

## Dependency Diagram

```mermaid
graph LR;
    classDef currentGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#000,stroke-width:2px;
    classDef internalEgGemStyle fill:#D4EFDF,stroke:#58D68D,color:#000;
    classDef externalGemStyle fill:#FADBD8,stroke:#EC7063,color:#000;
    elasticgraph-graphql_lambda["elasticgraph-graphql_lambda"];
    class elasticgraph-graphql_lambda currentGemStyle;
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-graphql_lambda --> elasticgraph-graphql;
    class elasticgraph-graphql internalEgGemStyle;
    elasticgraph-lambda_support["elasticgraph-lambda_support"];
    elasticgraph-graphql_lambda --> elasticgraph-lambda_support;
    class elasticgraph-lambda_support internalEgGemStyle;
```
