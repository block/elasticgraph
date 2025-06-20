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
    style elasticgraph color:DodgerBlue,stroke-width:2px,stroke:DodgerBlue;
    style elasticgraph-support color:Green,stroke:Green;
    style thor color:Red,stroke:Red;
    click thor href "https://rubygems.org/gems/thor" "Open on RubyGems.org" _blank;
```

## Getting Started

Run this command to bootstrap a new local project:

```bash
elasticgraph new my_app
```
