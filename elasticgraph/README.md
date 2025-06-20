# ElasticGraph

ElasticGraph meta-gem that pulls in all the core ElasticGraph gems. Intended for use when all
parts of ElasticGraph are used from the same deployed app.

## Dependency Diagram

```mermaid
graph LR;
    elasticgraph["elasticgraph"];
    elasticgraph-support["elasticgraph-support"];
    elasticgraph --> elasticgraph-support;
    thor["thor"];
    elasticgraph --> thor;
    style elasticgraph fill:#lightblue,stroke:#2980b9,stroke-width:2px,color:#000;
    style elasticgraph-support fill:#lightgreen,stroke:#27ae60,stroke-width:1px,color:#000;
    style thor fill:#lightcoral,stroke:#c0392b,stroke-width:1px,color:#000;
```

## Getting Started

Run this command to bootstrap a new local project:

```bash
elasticgraph new my_app
```
