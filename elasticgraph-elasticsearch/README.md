# ElasticGraph::Elasticsearch

Wraps the official Elasticsearch client for use by ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    classDef currentGemStyle fill:#AED6F1,stroke:#3498DB,color:#000,stroke-width:2px;
    classDef internalEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#FADBD8,stroke:#EC7063,color:#2980B9;
    elasticgraph-elasticsearch["elasticgraph-elasticsearch"];
    class elasticgraph-elasticsearch currentGemStyle;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-elasticsearch --> elasticgraph-support;
    class elasticgraph-support internalEgGemStyle;
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
