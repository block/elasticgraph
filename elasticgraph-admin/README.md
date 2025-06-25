# ElasticGraph::Admin

Administers a datastore for an ElasticGraph project.

## Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-admin["elasticgraph-admin"];
    class elasticgraph-admin targetGemStyle;
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    elasticgraph-admin --> elasticgraph-datastore_core;
    class elasticgraph-datastore_core otherEgGemStyle;
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-admin --> elasticgraph-indexer;
    class elasticgraph-indexer otherEgGemStyle;
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-admin --> elasticgraph-schema_artifacts;
    class elasticgraph-schema_artifacts otherEgGemStyle;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-admin --> elasticgraph-support;
    class elasticgraph-support otherEgGemStyle;
    rake["rake"];
    elasticgraph-admin --> rake;
    class rake externalGemStyle;
    elasticgraph-admin_lambda["elasticgraph-admin_lambda"];
    elasticgraph-admin_lambda --> elasticgraph-admin;
    class elasticgraph-admin_lambda otherEgGemStyle;
    elasticgraph-local["elasticgraph-local"];
    elasticgraph-local --> elasticgraph-admin;
    class elasticgraph-local otherEgGemStyle;
    click rake href "https://rubygems.org/gems/rake" "Open on RubyGems.org" _blank;
```

## Usage

This gem provides rake tasks for administering a datastore. To see what changes will be made, run:

```bash
bundle exec rake clusters:configure:dry_run
```

Then, to apply the changes, run:

```bash
bundle exec rake clusters:configure:perform
```

These tasks are automatically pulled into a project via `elasticgraph-local`, but they can also be manually
installed in a `Rakefile` (e.g. for production environments):

```ruby
# in Rakefile

require "elastic_graph/admin"
require "elastic_graph/admin/rake_tasks"

ElasticGraph::Admin::RakeTasks.new do
  ElasticGraph::Admin.from_yaml_file("config/settings/local.yaml")
end
```
