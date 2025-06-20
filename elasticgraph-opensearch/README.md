# ElasticGraph::OpenSearch

Wraps the official OpenSearch client for use by ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-opensearch["elasticgraph-opensearch"];
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-opensearch --> elasticgraph-support;
    faraday["faraday"];
    elasticgraph-opensearch --> faraday;
    faraday-retry["faraday-retry"];
    elasticgraph-opensearch --> faraday-retry;
    opensearch-ruby["opensearch-ruby"];
    elasticgraph-opensearch --> opensearch-ruby;
    elasticgraph-lambda_support["elasticgraph-lambda_support"];
    elasticgraph-lambda_support --> elasticgraph-opensearch;
    style elasticgraph-opensearch fill:#lightblue,stroke:#2980b9,stroke-width:2px,color:#000;
    style elasticgraph-support fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style faraday fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style faraday-retry fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style opensearch-ruby fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style elasticgraph-lambda_support fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
```
