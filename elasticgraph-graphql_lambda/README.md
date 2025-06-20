# ElasticGraph::GraphQLLambda

This gem wraps `elasticgraph-graphql` in order to run it from an AWS Lambda.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-graphql_lambda --> elasticgraph-graphql;
    elasticgraph-graphql_lambda --> elasticgraph-lambda_support;
    no_eg_dependents[(No direct EG dependents)] --> elasticgraph-graphql_lambda;
    classDef currentGemStyle fill:#lightblue,stroke:#333,stroke-width:2px;
    classDef internalEgGemStyle fill:#lightgreen,stroke:#333,stroke-width:1px;
    classDef externalGemStyle fill:#lightcoral,stroke:#333,stroke-width:1px;
    classDef placeholderNodeStyle fill:#eee,stroke:#333,stroke-width:1px;
    class elasticgraph-graphql_lambda currentGemStyle;
    class elasticgraph-graphql internalEgGemStyle;
    class elasticgraph-lambda_support internalEgGemStyle;
    class no_eg_dependents placeholderNodeStyle;
```
