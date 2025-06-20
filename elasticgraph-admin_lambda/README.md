# ElasticGraph::AdminLambda

This gem wraps `elasticgraph-admin` in order to run it from an AWS Lambda.

## Dependency Diagram

```mermaid
graph LR;
    classDef currentGemStyle fill:#AED6F1,stroke:#3498DB,color:#000,stroke-width:2px;
    classDef internalEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#F4F6F7,stroke:#B3B6B7,color:#2980B9;
    elasticgraph-admin_lambda["elasticgraph-admin_lambda"];
    class elasticgraph-admin_lambda currentGemStyle;
    rake["rake"];
    elasticgraph-admin_lambda --> rake;
    class rake externalGemStyle;
    elasticgraph-admin["elasticgraph-admin"];
    elasticgraph-admin_lambda --> elasticgraph-admin;
    class elasticgraph-admin internalEgGemStyle;
    elasticgraph-lambda_support["elasticgraph-lambda_support"];
    elasticgraph-admin_lambda --> elasticgraph-lambda_support;
    class elasticgraph-lambda_support internalEgGemStyle;
    click rake href "https://rubygems.org/gems/rake" "Open on RubyGems.org" _blank;
```
