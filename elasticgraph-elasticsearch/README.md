# ElasticGraph::Elasticsearch

Wraps the official Elasticsearch client for use by ElasticGraph.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph-elasticsearch["elasticgraph-elasticsearch"];
    elasticgraph-support["elasticgraph-support"];
    elasticgraph-elasticsearch --> elasticgraph-support;
    elasticsearch["elasticsearch"];
    elasticgraph-elasticsearch --> elasticsearch;
    faraday["faraday"];
    elasticgraph-elasticsearch --> faraday;
    faraday-retry["faraday-retry"];
    elasticgraph-elasticsearch --> faraday-retry;
    style elasticgraph-elasticsearch fill:#lightblue,stroke:#2980b9,stroke-width:2px,color:#000;
    style elasticgraph-support fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style elasticsearch fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style faraday fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
    style faraday-retry fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
```
