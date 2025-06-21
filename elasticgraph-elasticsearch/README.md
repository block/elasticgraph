# ElasticGraph::Elasticsearch

Wraps the official Elasticsearch client for use by ElasticGraph.

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
