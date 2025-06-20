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
    style elasticgraph-elasticsearch color:DodgerBlue,stroke-width:2px,stroke:DodgerBlue;
    style elasticgraph-support color:Green,stroke:Green;
    style elasticsearch color:Red,stroke:Red;
    style faraday color:Red,stroke:Red;
    style faraday-retry color:Red,stroke:Red;
    click elasticsearch href "https://rubygems.org/gems/elasticsearch" "Open on RubyGems.org" _blank;
    click faraday href "https://rubygems.org/gems/faraday" "Open on RubyGems.org" _blank;
    click faraday-retry href "https://rubygems.org/gems/faraday-retry" "Open on RubyGems.org" _blank;
```
