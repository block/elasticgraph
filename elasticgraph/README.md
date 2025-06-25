# ElasticGraph

Bootstraps ElasticGraph projects.

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

## Usage

Run one of these commands to bootstrap a new ElasticGraph project:

```bash
gem exec elasticgraph new path/to/project --datastore elasticsearch
# or
gem exec elasticgraph new path/to/project --datastore opensearch
```

See our [getting started guide](https://block.github.io/elasticgraph/getting-started/) for a full tutorial.
