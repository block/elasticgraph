# ElasticGraph::GraphQLLambda

This gem wraps `elasticgraph-graphql` in order to run it from an AWS Lambda.

## Dependency Diagram

```mermaid
graph LR;
    classDef currentGemStyle fill:#AED6F1,stroke:#3498DB,color:#000,stroke-width:2px;
    classDef internalEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#F4F6F7,stroke:#B3B6B7,color:#2980B9;
    elasticgraph-graphql_lambda["elasticgraph-graphql_lambda"];
    class elasticgraph-graphql_lambda currentGemStyle;
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-graphql_lambda --> elasticgraph-graphql;
    class elasticgraph-graphql internalEgGemStyle;
    elasticgraph-lambda_support["elasticgraph-lambda_support"];
    elasticgraph-graphql_lambda --> elasticgraph-lambda_support;
    class elasticgraph-lambda_support internalEgGemStyle;
```
