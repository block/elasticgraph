# ElasticGraph::AdminLambda

This gem wraps `elasticgraph-admin` in order to run it from an AWS Lambda.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-admin_lambda["elasticgraph-admin_lambda"];
    rake["rake"];
    elasticgraph-admin_lambda --> rake;
    elasticgraph-admin["elasticgraph-admin"];
    elasticgraph-admin_lambda --> elasticgraph-admin;
    elasticgraph-lambda_support["elasticgraph-lambda_support"];
    elasticgraph-admin_lambda --> elasticgraph-lambda_support;
    style elasticgraph-admin_lambda color:DodgerBlue,stroke-width:2px,stroke:DodgerBlue;
    style rake color:Red,stroke:Red;
    style elasticgraph-admin color:Green,stroke:Green;
    style elasticgraph-lambda_support color:Green,stroke:Green;
    click rake href "https://rubygems.org/gems/rake" "Open on RubyGems.org" _blank;
```
