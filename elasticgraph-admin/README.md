# ElasticGraph::Admin

Provides datastore administrative tasks for ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-admin["elasticgraph-admin"];
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    elasticgraph-admin --> elasticgraph-datastore_core;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-admin --> elasticgraph-indexer;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-admin --> elasticgraph-schema_artifacts;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-admin --> elasticgraph-support;
    rake["rake"];
    elasticgraph-admin --> rake;
    elasticgraph-admin_lambda["elasticgraph-admin_lambda"];
    elasticgraph-admin_lambda --> elasticgraph-admin;
    elasticgraph-local["elasticgraph-local"];
    elasticgraph-local --> elasticgraph-admin;
    style elasticgraph-admin color:DodgerBlue,stroke-width:2px,stroke:DodgerBlue;
    style elasticgraph-datastore_core color:Green,stroke:Green;
    style elasticgraph-indexer color:Green,stroke:Green;
    style elasticgraph-schema_artifacts color:Green,stroke:Green;
    style elasticgraph-support color:Green,stroke:Green;
    style rake color:Red,stroke:Red;
    style elasticgraph-admin_lambda color:Green,stroke:Green;
    style elasticgraph-local color:Green,stroke:Green;
    click rake href "https://rubygems.org/gems/rake" "Open on RubyGems.org" _blank;
```
