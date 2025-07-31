# ElasticGraph::Elasticsearch

Wraps the official [Elasticsearch client](https://github.com/elastic/elasticsearch-ruby) for use by ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-elasticsearch["elasticgraph-elasticsearch"];
    class elasticgraph-elasticsearch targetGemStyle;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-elasticsearch --> elasticgraph-support;
    class elasticgraph-support otherEgGemStyle;
    elasticsearch["elasticsearch"];
    elasticgraph-elasticsearch --> elasticsearch;
    class elasticsearch externalGemStyle;
    faraday["faraday"];
    elasticgraph-elasticsearch --> faraday;
    class faraday externalGemStyle;
    faraday-retry["faraday-retry"];
    elasticgraph-elasticsearch --> faraday-retry;
    class faraday-retry externalGemStyle;
    click elasticsearch href "https://rubygems.org/gems/elasticsearch" "Open on RubyGems.org" _blank;
    click faraday href "https://rubygems.org/gems/faraday" "Open on RubyGems.org" _blank;
    click faraday-retry href "https://rubygems.org/gems/faraday-retry" "Open on RubyGems.org" _blank;
```

## Usage

ElasticGraph projects are configured to use this gem or `elasticgraph-opensearch`, based on which datastore is being used.

To use an ElasticGraph project with Elasticsearch, bootstrap an ElasticGraph project with `--datastore elasticsearch`:

```bash
gem exec elasticgraph new path/to/project --datastore elasticsearch
```

### Migrate from OpenSearch to Elasticsearch

If you need to convert an existing project to use Elasticsearch instead of OpenSearch, here's how to do that.

First, replace `elasticgraph-opensearch` with `elasticgraph-elasticsearch` in the `Gemfile`:

```diff
diff --git a/Gemfile b/Gemfile
index 4a5ef1e..cc0e1fb 100644
--- a/Gemfile
+++ b/Gemfile
@@ -7,7 +7,7 @@ gem "elasticgraph-local", *elasticgraph_details
 gem "elasticgraph-query_registry", *elasticgraph_details

 # Can be elasticgraph-elasticsearch or elasticgraph-opensearch based on the datastore you want to use.
-gem "elasticgraph-opensearch", *elasticgraph_details
+gem "elasticgraph-elasticsearch", *elasticgraph_details

 gem "httpx", "~> 1.3"

```

Then, update the settings YAML file to configure `elasticsearch` as the cluster backend:

```diff
diff --git a/config/settings/local.yaml b/config/settings/local.yaml
index 963f4f9..16eb063 100644
--- a/config/settings/local.yaml
+++ b/config/settings/local.yaml
@@ -4,7 +4,7 @@ datastore:
     require: httpx/adapters/faraday
   clusters:
     main:
-      backend: opensearch
+      backend: elasticsearch
       url: http://localhost:9200
       settings: {}
   index_definitions:
```
