# ElasticGraph

ElasticGraph meta-gem that pulls in all the core ElasticGraph gems. Intended for use when all
parts of ElasticGraph are used from the same deployed app.

## Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph["elasticgraph"];
    class elasticgraph targetGemStyle;
    elasticgraph-support["elasticgraph-support"];
    elasticgraph --> elasticgraph-support;
    class elasticgraph-support otherEgGemStyle;
    thor["thor"];
    elasticgraph --> thor;
    class thor externalGemStyle;
    click thor href "https://rubygems.org/gems/thor" "Open on RubyGems.org" _blank;
```

## Getting Started

Run this command to bootstrap a new local project:

```
elasticgraph new my_app
```
