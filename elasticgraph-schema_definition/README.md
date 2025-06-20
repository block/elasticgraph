# ElasticGraph::SchemaDefinition

Provides the ElasticGraph schema definition API, which is used to
generate ElasticGraph's schema artifacts.

This gem is not intended to be used in production--production should
just use the schema artifacts instead.

## Dependency Diagram

```mermaid
graph LR;
    classDef currentGemStyle fill:#AED6F1,stroke:#3498DB,color:#000,stroke-width:2px;
    classDef internalEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#FADBD8,stroke:#EC7063,color:#2980B9;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    class elasticgraph-schema_definition currentGemStyle;
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-schema_definition --> elasticgraph-graphql;
    class elasticgraph-graphql internalEgGemStyle;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-schema_definition --> elasticgraph-indexer;
    class elasticgraph-indexer internalEgGemStyle;
    elasticgraph-json_schema["elasticgraph-json_schema"];
    elasticgraph-schema_definition --> elasticgraph-json_schema;
    class elasticgraph-json_schema internalEgGemStyle;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-schema_definition --> elasticgraph-schema_artifacts;
    class elasticgraph-schema_artifacts internalEgGemStyle;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-schema_definition --> elasticgraph-support;
    class elasticgraph-support internalEgGemStyle;
    graphql["graphql"];
    elasticgraph-schema_definition --> graphql;
    class graphql externalGemStyle;
    graphql-c_parser["graphql-c_parser"];
    elasticgraph-schema_definition --> graphql-c_parser;
    class graphql-c_parser externalGemStyle;
    rake["rake"];
    elasticgraph-schema_definition --> rake;
    class rake externalGemStyle;
    elasticgraph-local["elasticgraph-local"];
    elasticgraph-local --> elasticgraph-schema_definition;
    class elasticgraph-local internalEgGemStyle;
    click graphql href "https://rubygems.org/gems/graphql" "Open on RubyGems.org" _blank;
    click graphql-c_parser href "https://rubygems.org/gems/graphql-c_parser" "Open on RubyGems.org" _blank;
    click rake href "https://rubygems.org/gems/rake" "Open on RubyGems.org" _blank;
```
