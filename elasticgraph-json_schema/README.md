# ElasticGraph::JSONSchema

Provides JSON Schema validation for ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-json_schema["elasticgraph-json_schema"];
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-json_schema --> elasticgraph-support;
    json_schemer["json_schemer"];
    elasticgraph-json_schema --> json_schemer;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-indexer --> elasticgraph-json_schema;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-schema_definition --> elasticgraph-json_schema;
    style elasticgraph-json_schema color:DodgerBlue,stroke-width:2px,stroke:DodgerBlue;
    style elasticgraph-support color:Green,stroke:Green;
    style json_schemer color:Red,stroke:Red;
    style elasticgraph-indexer color:Green,stroke:Green;
    style elasticgraph-schema_definition color:Green,stroke:Green;
    click json_schemer href "https://rubygems.org/gems/json_schemer" "Open on RubyGems.org" _blank;
```
