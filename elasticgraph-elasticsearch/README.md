# ElasticGraph::Elasticsearch

Wraps the official Elasticsearch client for use by ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    classDef currentGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#000,stroke-width:2px;
    classDef internalEgGemStyle fill:#D4EFDF,stroke:#58D68D,color:#000;
    classDef externalGemStyle fill:#FADBD8,stroke:#EC7063,color:#000;
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
