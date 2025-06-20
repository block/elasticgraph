# ElasticGraph::GraphQL

Provides the ElasticGraph GraphQL query engine.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-graphql["elasticgraph-graphql"];
    base64["base64"];
    elasticgraph-graphql --> base64;
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    elasticgraph-graphql --> elasticgraph-datastore_core;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-graphql --> elasticgraph-schema_artifacts;
    graphql["graphql"];
    elasticgraph-graphql --> graphql;
    graphql-c_parser["graphql-c_parser"];
    elasticgraph-graphql --> graphql-c_parser;
    elasticgraph-apollo["elasticgraph-apollo"];
    elasticgraph-apollo --> elasticgraph-graphql;
    elasticgraph-graphql_lambda["elasticgraph-graphql_lambda"];
    elasticgraph-graphql_lambda --> elasticgraph-graphql;
    elasticgraph-health_check["elasticgraph-health_check"];
    elasticgraph-health_check --> elasticgraph-graphql;
    elasticgraph-local["elasticgraph-local"];
    elasticgraph-local --> elasticgraph-graphql;
    elasticgraph-query_interceptor["elasticgraph-query_interceptor"];
    elasticgraph-query_interceptor --> elasticgraph-graphql;
    elasticgraph-query_registry["elasticgraph-query_registry"];
    elasticgraph-query_registry --> elasticgraph-graphql;
    elasticgraph-rack["elasticgraph-rack"];
    elasticgraph-rack --> elasticgraph-graphql;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-schema_definition --> elasticgraph-graphql;
    style elasticgraph-graphql color:DodgerBlue,stroke-width:2px,stroke:DodgerBlue;
    style base64 color:Red,stroke:Red;
    style elasticgraph-datastore_core color:Green,stroke:Green;
    style elasticgraph-schema_artifacts color:Green,stroke:Green;
    style graphql color:Red,stroke:Red;
    style graphql-c_parser color:Red,stroke:Red;
    style elasticgraph-apollo color:Green,stroke:Green;
    style elasticgraph-graphql_lambda color:Green,stroke:Green;
    style elasticgraph-health_check color:Green,stroke:Green;
    style elasticgraph-local color:Green,stroke:Green;
    style elasticgraph-query_interceptor color:Green,stroke:Green;
    style elasticgraph-query_registry color:Green,stroke:Green;
    style elasticgraph-rack color:Green,stroke:Green;
    style elasticgraph-schema_definition color:Green,stroke:Green;
    click base64 href "https://rubygems.org/gems/base64" "Open on RubyGems.org" _blank;
    click graphql href "https://rubygems.org/gems/graphql" "Open on RubyGems.org" _blank;
    click graphql-c_parser href "https://rubygems.org/gems/graphql-c_parser" "Open on RubyGems.org" _blank;
```
