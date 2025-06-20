# ElasticGraph

ElasticGraph meta-gem that pulls in all the core ElasticGraph gems. Intended for use when all
parts of ElasticGraph are used from the same deployed app.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph --> elasticgraph-support;
    elasticgraph --> thor;
    no_eg_dependents[(No direct EG dependents)] --> elasticgraph;
    classDef currentGemStyle fill:#lightblue,stroke:#333,stroke-width:2px;
    classDef internalEgGemStyle fill:#lightgreen,stroke:#333,stroke-width:1px;
    classDef externalGemStyle fill:#lightcoral,stroke:#333,stroke-width:1px;
    classDef placeholderNodeStyle fill:#eee,stroke:#333,stroke-width:1px;
    class elasticgraph currentGemStyle;
    class elasticgraph-support internalEgGemStyle;
    class thor externalGemStyle;
    class no_eg_dependents placeholderNodeStyle;
```

## Getting Started

Run this command to bootstrap a new local project:

```bash
elasticgraph new my_app
```
