# ElasticGraph::SchemaDefinition

Provides the ElasticGraph schema definition API, which is used to
generate ElasticGraph's schema artifacts.

This gem is not intended to be used in production--production should
just use the schema artifacts instead.

## Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    class elasticgraph-schema_definition targetGemStyle;
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-schema_definition --> elasticgraph-graphql;
    class elasticgraph-graphql otherEgGemStyle;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-schema_definition --> elasticgraph-indexer;
    class elasticgraph-indexer otherEgGemStyle;
    elasticgraph-json_schema["elasticgraph-json_schema"];
    elasticgraph-schema_definition --> elasticgraph-json_schema;
    class elasticgraph-json_schema otherEgGemStyle;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-schema_definition --> elasticgraph-schema_artifacts;
    class elasticgraph-schema_artifacts otherEgGemStyle;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-schema_definition --> elasticgraph-support;
    class elasticgraph-support otherEgGemStyle;
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
    class elasticgraph-local otherEgGemStyle;
    click graphql href "https://rubygems.org/gems/graphql" "Open on RubyGems.org" _blank;
    click graphql-c_parser href "https://rubygems.org/gems/graphql-c_parser" "Open on RubyGems.org" _blank;
    click rake href "https://rubygems.org/gems/rake" "Open on RubyGems.org" _blank;
```

## Usage

Define the shape of your data using the schema definition API:

```ruby
# in config/schema/team.rb

ElasticGraph.define_schema do |schema|
  schema.enum_type "SportsLeague" do |t|
    t.value "MLB"
    t.value "NBA"
    t.value "NFL"
    t.value "NHL"
  end

  schema.object_type "Team" do |t|
    t.field "id", "ID!"
    t.field "league", "SportsLeague"
    t.field "formedOn", "Date"
    t.field "currentName", "String"
    t.field "pastNames", "[String!]!"
    t.field "stadiumLocation", "GeoLocation"

    t.index "teams"
  end
end
```

The default rake task (`bundle exec rake`) performs a full build, including generating schema artifacts.
You can directly generate schema artifacts with:

```bash
bundle exec rake schema_artifacts:dump
```

To see if the artifacts are up-to-date, run:

```bash
bundle exec rake schema_artifacts:check
```
