# ElasticGraph::SchemaDefinition

Provides the ElasticGraph schema definition API, which is used to
generate ElasticGraph's schema artifacts.

This gem is not intended to be used in production--production should
just use the schema artifacts instead.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-schema_definition --> elasticgraph-graphql;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-schema_definition --> elasticgraph-indexer;
    elasticgraph-json_schema["elasticgraph-json_schema"];
    elasticgraph-schema_definition --> elasticgraph-json_schema;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-schema_definition --> elasticgraph-schema_artifacts;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-schema_definition --> elasticgraph-support;
    graphql["graphql"];
    elasticgraph-schema_definition --> graphql;
    graphql-c_parser["graphql-c_parser"];
    elasticgraph-schema_definition --> graphql-c_parser;
    rake["rake"];
    elasticgraph-schema_definition --> rake;
    elasticgraph-local["elasticgraph-local"];
    elasticgraph-local --> elasticgraph-schema_definition;
    style elasticgraph-schema_definition color:DodgerBlue,stroke-width:2px,stroke:DodgerBlue;
    style elasticgraph-graphql color:Green,stroke:Green;
    style elasticgraph-indexer color:Green,stroke:Green;
    style elasticgraph-json_schema color:Green,stroke:Green;
    style elasticgraph-schema_artifacts color:Green,stroke:Green;
    style elasticgraph-support color:Green,stroke:Green;
    style graphql color:Red,stroke:Red;
    style graphql-c_parser color:Red,stroke:Red;
    style rake color:Red,stroke:Red;
    style elasticgraph-local color:Green,stroke:Green;
    click graphql href "https://rubygems.org/gems/graphql" "Open on RubyGems.org" _blank;
    click graphql-c_parser href "https://rubygems.org/gems/graphql-c_parser" "Open on RubyGems.org" _blank;
    click rake href "https://rubygems.org/gems/rake" "Open on RubyGems.org" _blank;
```
