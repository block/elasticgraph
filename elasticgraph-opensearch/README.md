# ElasticGraph::OpenSearch

Wraps the official OpenSearch client for use by ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    classDef currentGemStyle fill:#AED6F1,stroke:#3498DB,color:#000,stroke-width:2px;
    classDef internalEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#FADBD8,stroke:#EC7063,color:#2980B9;
    elasticgraph-opensearch["elasticgraph-opensearch"];
    class elasticgraph-opensearch currentGemStyle;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-opensearch --> elasticgraph-support;
    class elasticgraph-support internalEgGemStyle;
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
    class elasticgraph-lambda_support internalEgGemStyle;
    click faraday href "https://rubygems.org/gems/faraday" "Open on RubyGems.org" _blank;
    click faraday-retry href "https://rubygems.org/gems/faraday-retry" "Open on RubyGems.org" _blank;
    click opensearch-ruby href "https://rubygems.org/gems/opensearch-ruby" "Open on RubyGems.org" _blank;
```
