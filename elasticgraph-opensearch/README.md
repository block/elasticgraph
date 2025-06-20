# ElasticGraph::OpenSearch

Wraps the official OpenSearch client for use by ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-opensearch --> elasticgraph-support;
    elasticgraph-opensearch --> faraday;
    elasticgraph-opensearch --> faraday-retry;
    elasticgraph-opensearch --> opensearch-ruby;
    elasticgraph-lambda_support --> elasticgraph-opensearch;
    classDef currentGemStyle fill:#lightblue,stroke:#333,stroke-width:2px;
    classDef internalEgGemStyle fill:#lightgreen,stroke:#333,stroke-width:1px;
    classDef externalGemStyle fill:#lightcoral,stroke:#333,stroke-width:1px;
    classDef placeholderNodeStyle fill:#eee,stroke:#333,stroke-width:1px;
    class elasticgraph-opensearch currentGemStyle;
    class elasticgraph-support internalEgGemStyle;
    class faraday externalGemStyle;
    class faraday-retry externalGemStyle;
    class opensearch-ruby externalGemStyle;
    class elasticgraph-lambda_support internalEgGemStyle;
```
