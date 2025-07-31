# ElasticGraph::OpenSearch

Wraps the official [OpenSearch client](https://github.com/opensearch-project/opensearch-ruby/) for use by ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-opensearch["elasticgraph-opensearch"];
    class elasticgraph-opensearch targetGemStyle;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-opensearch --> elasticgraph-support;
    class elasticgraph-support otherEgGemStyle;
    faraday["faraday"];
    elasticgraph-opensearch --> faraday;
    class faraday externalGemStyle;
    faraday-retry["faraday-retry"];
    elasticgraph-opensearch --> faraday-retry;
    class faraday-retry externalGemStyle;
    opensearch-ruby["opensearch-ruby"];
    elasticgraph-opensearch --> opensearch-ruby;
    class opensearch-ruby externalGemStyle;
    elasticgraph-lambda_support["elasticgraph-lambda_support"];
    elasticgraph-lambda_support --> elasticgraph-opensearch;
    class elasticgraph-lambda_support otherEgGemStyle;
    click faraday href "https://rubygems.org/gems/faraday" "Open on RubyGems.org" _blank;
    click faraday-retry href "https://rubygems.org/gems/faraday-retry" "Open on RubyGems.org" _blank;
    click opensearch-ruby href "https://rubygems.org/gems/opensearch-ruby" "Open on RubyGems.org" _blank;
```

## Usage

ElasticGraph projects are configured to use this gem or `elasticgraph-elasticsearch`, based on which datastore is being used.

To use an ElasticGraph project with OpenSearch, bootstrap an ElasticGraph project with `--datastore opensearch`:

```bash
gem exec elasticgraph new path/to/project --datastore opensearch
```

### Migrate from Elasticsearch to OpenSearch

If you need to convert an existing project to use OpenSearch instead of Elasticsearch, here's how to do that.

First, replace `elasticgraph-elasticsearch` with `elasticgraph-opensearch` in the `Gemfile`:

```diff
diff --git a/Gemfile b/Gemfile
index 4a5ef1e..cc0e1fb 100644
--- a/Gemfile
+++ b/Gemfile
@@ -7,7 +7,7 @@ gem "elasticgraph-local", *elasticgraph_details
 gem "elasticgraph-query_registry", *elasticgraph_details

 # Can be elasticgraph-elasticsearch or elasticgraph-opensearch based on the datastore you want to use.
-gem "elasticgraph-elasticsearch", *elasticgraph_details
+gem "elasticgraph-opensearch", *elasticgraph_details

 gem "httpx", "~> 1.3"

```

Then, update the settings YAML file to configure `opensearch` as the cluster backend:

```diff
diff --git a/config/settings/local.yaml b/config/settings/local.yaml
index 963f4f9..16eb063 100644
--- a/config/settings/local.yaml
+++ b/config/settings/local.yaml
@@ -4,7 +4,7 @@ datastore:
     require: httpx/adapters/faraday
   clusters:
     main:
-      backend: elasticsearch
+      backend: opensearch
       url: http://localhost:9200
       settings: {}
   index_definitions:
```
