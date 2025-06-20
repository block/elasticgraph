# ElasticGraph::AdminLambda

This gem wraps `elasticgraph-admin` in order to run it from an AWS Lambda.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-admin_lambda --> rake;
    elasticgraph-admin_lambda --> elasticgraph-admin;
    elasticgraph-admin_lambda --> elasticgraph-lambda_support;
    no_eg_dependents[(No direct EG dependents)] --> elasticgraph-admin_lambda;
    classDef currentGemStyle fill:#lightblue,stroke:#333,stroke-width:2px;
    classDef internalEgGemStyle fill:#lightgreen,stroke:#333,stroke-width:1px;
    classDef externalGemStyle fill:#lightcoral,stroke:#333,stroke-width:1px;
    classDef placeholderNodeStyle fill:#eee,stroke:#333,stroke-width:1px;
    class elasticgraph-admin_lambda currentGemStyle;
    class rake externalGemStyle;
    class elasticgraph-admin internalEgGemStyle;
    class elasticgraph-lambda_support internalEgGemStyle;
    class no_eg_dependents placeholderNodeStyle;
```
