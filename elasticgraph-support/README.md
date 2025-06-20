# ElasticGraph::Support

This gem provides support utilities for the rest of the ElasticGraph gems. As
such, it is not intended to provide any public APIs for ElasticGraph users.

Importantly, it is intended to have as few dependencies as possible: it currently
only depends on `logger` (which originated in the Ruby standard library).

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-support["elasticgraph-support"];
    logger["logger"];
    elasticgraph-support --> logger;
    elasticgraph["elasticgraph"];
    elasticgraph --> elasticgraph-support;
    elasticgraph-admin["elasticgraph-admin"];
    elasticgraph-admin --> elasticgraph-support;
    elasticgraph-apollo["elasticgraph-apollo"];
    elasticgraph-apollo --> elasticgraph-support;
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    elasticgraph-datastore_core --> elasticgraph-support;
    elasticgraph-elasticsearch["elasticgraph-elasticsearch"];
    elasticgraph-elasticsearch --> elasticgraph-support;
    elasticgraph-health_check["elasticgraph-health_check"];
    elasticgraph-health_check --> elasticgraph-support;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-indexer --> elasticgraph-support;
    elasticgraph-json_schema["elasticgraph-json_schema"];
    elasticgraph-json_schema --> elasticgraph-support;
    elasticgraph-opensearch["elasticgraph-opensearch"];
    elasticgraph-opensearch --> elasticgraph-support;
    elasticgraph-query_registry["elasticgraph-query_registry"];
    elasticgraph-query_registry --> elasticgraph-support;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-schema_artifacts --> elasticgraph-support;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    elasticgraph-schema_definition --> elasticgraph-support;
    style elasticgraph-support color:DodgerBlue,stroke-width:2px,stroke:DodgerBlue;
    style logger color:Red,stroke:Red;
    style elasticgraph color:Green,stroke:Green;
    style elasticgraph-admin color:Green,stroke:Green;
    style elasticgraph-apollo color:Green,stroke:Green;
    style elasticgraph-datastore_core color:Green,stroke:Green;
    style elasticgraph-elasticsearch color:Green,stroke:Green;
    style elasticgraph-health_check color:Green,stroke:Green;
    style elasticgraph-indexer color:Green,stroke:Green;
    style elasticgraph-json_schema color:Green,stroke:Green;
    style elasticgraph-opensearch color:Green,stroke:Green;
    style elasticgraph-query_registry color:Green,stroke:Green;
    style elasticgraph-schema_artifacts color:Green,stroke:Green;
    style elasticgraph-schema_definition color:Green,stroke:Green;
    click logger href "https://rubygems.org/gems/logger" "Open on RubyGems.org" _blank;
```
