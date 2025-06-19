# ElasticGraph Codebase Overview

ElasticGraph is designed to be modular, with a small core, and many built-in extensions that extend that core
for specific use cases. This minimizes exposure to vulnerabilities, reduces bloat, and makes ongoing upgrades
easier. The libraries that ship with ElasticGraph can be broken down into several categories.

### Core Libraries (7 gems)

These libraries form the core backbone of ElasticGraph that is designed to run in a production deployment. Every ElasticGraph deployment will need to use all of these.

* [elasticgraph-admin](elasticgraph-admin/README.md): ElasticGraph gem that provides datastore administrative tasks, to keep a datastore up-to-date with an ElasticGraph schema.
* [elasticgraph-datastore_core](elasticgraph-datastore_core/README.md): ElasticGraph gem containing the core datastore support types and logic.
* [elasticgraph-graphql](elasticgraph-graphql/README.md): The ElasticGraph GraphQL query engine.
* [elasticgraph-indexer](elasticgraph-indexer/README.md): ElasticGraph gem that provides APIs to robustly index data into a datastore.
* [elasticgraph-json_schema](elasticgraph-json_schema/README.md): ElasticGraph gem that provides JSON Schema validation.
* [elasticgraph-schema_artifacts](elasticgraph-schema_artifacts/README.md): ElasticGraph gem containing code related to generated schema artifacts.
* [elasticgraph-support](elasticgraph-support/README.md): ElasticGraph gem providing support utilities to the other ElasticGraph gems.

#### Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemCatStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-admin["elasticgraph-admin"];
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-support["elasticgraph-support"];
    rake["rake"];
    elasticgraph-graphql["elasticgraph-graphql"];
    base64["base64"];
    graphql["graphql"];
    graphql-c_parser["graphql-c_parser"];
    elasticgraph-json_schema["elasticgraph-json_schema"];
    hashdiff["hashdiff"];
    json_schemer["json_schemer"];
    logger["logger"];
    elasticgraph-admin --> elasticgraph-datastore_core;
    elasticgraph-admin --> elasticgraph-indexer;
    elasticgraph-admin --> elasticgraph-schema_artifacts;
    elasticgraph-admin --> elasticgraph-support;
    elasticgraph-admin --> rake;
    elasticgraph-datastore_core --> elasticgraph-schema_artifacts;
    elasticgraph-datastore_core --> elasticgraph-support;
    elasticgraph-graphql --> base64;
    elasticgraph-graphql --> elasticgraph-datastore_core;
    elasticgraph-graphql --> elasticgraph-schema_artifacts;
    elasticgraph-graphql --> graphql;
    elasticgraph-graphql --> graphql-c_parser;
    elasticgraph-indexer --> elasticgraph-datastore_core;
    elasticgraph-indexer --> elasticgraph-json_schema;
    elasticgraph-indexer --> elasticgraph-schema_artifacts;
    elasticgraph-indexer --> elasticgraph-support;
    elasticgraph-indexer --> hashdiff;
    elasticgraph-json_schema --> elasticgraph-support;
    elasticgraph-json_schema --> json_schemer;
    elasticgraph-schema_artifacts --> elasticgraph-support;
    elasticgraph-support --> logger;
    class elasticgraph-admin targetGemStyle;
    class elasticgraph-datastore_core targetGemStyle;
    class elasticgraph-indexer targetGemStyle;
    class elasticgraph-schema_artifacts targetGemStyle;
    class elasticgraph-support targetGemStyle;
    class rake externalGemCatStyle;
    class elasticgraph-graphql targetGemStyle;
    class base64 externalGemCatStyle;
    class graphql externalGemCatStyle;
    class graphql-c_parser externalGemCatStyle;
    class elasticgraph-json_schema targetGemStyle;
    class hashdiff externalGemCatStyle;
    class json_schemer externalGemCatStyle;
    class logger externalGemCatStyle;
    click rake href "https://rubygems.org/gems/rake" "Open on RubyGems.org" _blank;
    click base64 href "https://rubygems.org/gems/base64" "Open on RubyGems.org" _blank;
    click graphql href "https://rubygems.org/gems/graphql" "Open on RubyGems.org" _blank;
    click graphql-c_parser href "https://rubygems.org/gems/graphql-c_parser" "Open on RubyGems.org" _blank;
    click hashdiff href "https://rubygems.org/gems/hashdiff" "Open on RubyGems.org" _blank;
    click json_schemer href "https://rubygems.org/gems/json_schemer" "Open on RubyGems.org" _blank;
    click logger href "https://rubygems.org/gems/logger" "Open on RubyGems.org" _blank;
```

### AWS Lambda Integration Libraries (5 gems)

These libraries wrap the the core ElasticGraph libraries so that they can be deployed using AWS Lambda.

* [elasticgraph-admin_lambda](elasticgraph-admin_lambda/README.md): ElasticGraph gem that wraps elasticgraph-admin in an AWS Lambda.
* [elasticgraph-graphql_lambda](elasticgraph-graphql_lambda/README.md): ElasticGraph gem that wraps elasticgraph-graphql in an AWS Lambda.
* [elasticgraph-indexer_autoscaler_lambda](elasticgraph-indexer_autoscaler_lambda/README.md): ElasticGraph gem that monitors OpenSearch CPU utilization to autoscale indexer lambda concurrency.
* [elasticgraph-indexer_lambda](elasticgraph-indexer_lambda/README.md): Provides an AWS Lambda interface for an elasticgraph API
* [elasticgraph-lambda_support](elasticgraph-lambda_support/README.md): ElasticGraph gem that supports running ElasticGraph using AWS Lambda.

#### Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemCatStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-admin_lambda["elasticgraph-admin_lambda"];
    rake["rake"];
    elasticgraph-admin["elasticgraph-admin"];
    elasticgraph-lambda_support["elasticgraph-lambda_support"];
    elasticgraph-graphql_lambda["elasticgraph-graphql_lambda"];
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-indexer_autoscaler_lambda["elasticgraph-indexer_autoscaler_lambda"];
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    aws-sdk-lambda["aws-sdk-lambda"];
    aws-sdk-sqs["aws-sdk-sqs"];
    aws-sdk-cloudwatch["aws-sdk-cloudwatch"];
    ox["ox"];
    elasticgraph-indexer_lambda["elasticgraph-indexer_lambda"];
    elasticgraph-indexer["elasticgraph-indexer"];
    aws-sdk-s3["aws-sdk-s3"];
    elasticgraph-opensearch["elasticgraph-opensearch"];
    faraday_middleware-aws-sigv4["faraday_middleware-aws-sigv4"];
    elasticgraph-admin_lambda --> rake;
    elasticgraph-admin_lambda --> elasticgraph-admin;
    elasticgraph-admin_lambda --> elasticgraph-lambda_support;
    elasticgraph-graphql_lambda --> elasticgraph-graphql;
    elasticgraph-graphql_lambda --> elasticgraph-lambda_support;
    elasticgraph-indexer_autoscaler_lambda --> elasticgraph-datastore_core;
    elasticgraph-indexer_autoscaler_lambda --> elasticgraph-lambda_support;
    elasticgraph-indexer_autoscaler_lambda --> aws-sdk-lambda;
    elasticgraph-indexer_autoscaler_lambda --> aws-sdk-sqs;
    elasticgraph-indexer_autoscaler_lambda --> aws-sdk-cloudwatch;
    elasticgraph-indexer_autoscaler_lambda --> ox;
    elasticgraph-indexer_lambda --> elasticgraph-indexer;
    elasticgraph-indexer_lambda --> elasticgraph-lambda_support;
    elasticgraph-indexer_lambda --> aws-sdk-s3;
    elasticgraph-indexer_lambda --> ox;
    elasticgraph-lambda_support --> elasticgraph-opensearch;
    elasticgraph-lambda_support --> faraday_middleware-aws-sigv4;
    class elasticgraph-admin_lambda targetGemStyle;
    class rake externalGemCatStyle;
    class elasticgraph-admin otherEgGemStyle;
    class elasticgraph-lambda_support targetGemStyle;
    class elasticgraph-graphql_lambda targetGemStyle;
    class elasticgraph-graphql otherEgGemStyle;
    class elasticgraph-indexer_autoscaler_lambda targetGemStyle;
    class elasticgraph-datastore_core otherEgGemStyle;
    class aws-sdk-lambda externalGemCatStyle;
    class aws-sdk-sqs externalGemCatStyle;
    class aws-sdk-cloudwatch externalGemCatStyle;
    class ox externalGemCatStyle;
    class elasticgraph-indexer_lambda targetGemStyle;
    class elasticgraph-indexer otherEgGemStyle;
    class aws-sdk-s3 externalGemCatStyle;
    class elasticgraph-opensearch otherEgGemStyle;
    class faraday_middleware-aws-sigv4 externalGemCatStyle;
    click rake href "https://rubygems.org/gems/rake" "Open on RubyGems.org" _blank;
    click aws-sdk-lambda href "https://rubygems.org/gems/aws-sdk-lambda" "Open on RubyGems.org" _blank;
    click aws-sdk-sqs href "https://rubygems.org/gems/aws-sdk-sqs" "Open on RubyGems.org" _blank;
    click aws-sdk-cloudwatch href "https://rubygems.org/gems/aws-sdk-cloudwatch" "Open on RubyGems.org" _blank;
    click ox href "https://rubygems.org/gems/ox" "Open on RubyGems.org" _blank;
    click aws-sdk-s3 href "https://rubygems.org/gems/aws-sdk-s3" "Open on RubyGems.org" _blank;
    click faraday_middleware-aws-sigv4 href "https://rubygems.org/gems/faraday_middleware-aws-sigv4" "Open on RubyGems.org" _blank;
```

### Extensions (4 gems)

These libraries extend ElasticGraph to provide optional but commonly needed functionality.

* [elasticgraph-apollo](elasticgraph-apollo/README.md): An ElasticGraph extension that implements the Apollo federation spec.
* [elasticgraph-health_check](elasticgraph-health_check/README.md): An ElasticGraph extension that provides a health check for high availability deployments.
* [elasticgraph-query_interceptor](elasticgraph-query_interceptor/README.md): An ElasticGraph extension for intercepting datastore queries.
* [elasticgraph-query_registry](elasticgraph-query_registry/README.md): An ElasticGraph extension that supports safer schema evolution by limiting GraphQL queries based on a registry and validating registered queries against the schema.

#### Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemCatStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-apollo["elasticgraph-apollo"];
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-support["elasticgraph-support"];
    graphql["graphql"];
    apollo-federation["apollo-federation"];
    elasticgraph-health_check["elasticgraph-health_check"];
    elasticgraph-datastore_core["elasticgraph-datastore_core"];
    elasticgraph-query_interceptor["elasticgraph-query_interceptor"];
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    elasticgraph-query_registry["elasticgraph-query_registry"];
    graphql-c_parser["graphql-c_parser"];
    rake["rake"];
    elasticgraph-apollo --> elasticgraph-graphql;
    elasticgraph-apollo --> elasticgraph-support;
    elasticgraph-apollo --> graphql;
    elasticgraph-apollo --> apollo-federation;
    elasticgraph-health_check --> elasticgraph-datastore_core;
    elasticgraph-health_check --> elasticgraph-graphql;
    elasticgraph-health_check --> elasticgraph-support;
    elasticgraph-query_interceptor --> elasticgraph-graphql;
    elasticgraph-query_interceptor --> elasticgraph-schema_artifacts;
    elasticgraph-query_registry --> elasticgraph-graphql;
    elasticgraph-query_registry --> elasticgraph-support;
    elasticgraph-query_registry --> graphql;
    elasticgraph-query_registry --> graphql-c_parser;
    elasticgraph-query_registry --> rake;
    class elasticgraph-apollo targetGemStyle;
    class elasticgraph-graphql otherEgGemStyle;
    class elasticgraph-support otherEgGemStyle;
    class graphql externalGemCatStyle;
    class apollo-federation externalGemCatStyle;
    class elasticgraph-health_check targetGemStyle;
    class elasticgraph-datastore_core otherEgGemStyle;
    class elasticgraph-query_interceptor targetGemStyle;
    class elasticgraph-schema_artifacts otherEgGemStyle;
    class elasticgraph-query_registry targetGemStyle;
    class graphql-c_parser externalGemCatStyle;
    class rake externalGemCatStyle;
    click graphql href "https://rubygems.org/gems/graphql" "Open on RubyGems.org" _blank;
    click apollo-federation href "https://rubygems.org/gems/apollo-federation" "Open on RubyGems.org" _blank;
    click graphql-c_parser href "https://rubygems.org/gems/graphql-c_parser" "Open on RubyGems.org" _blank;
    click rake href "https://rubygems.org/gems/rake" "Open on RubyGems.org" _blank;
```

### Datastore Adapters (2 gems)

These libraries adapt ElasticGraph to your choice of datastore (Elasticsearch or OpenSearch).

* [elasticgraph-elasticsearch](elasticgraph-elasticsearch/README.md): Wraps the Elasticsearch client for use by ElasticGraph.
* [elasticgraph-opensearch](elasticgraph-opensearch/README.md): Wraps the OpenSearch client for use by ElasticGraph.

#### Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemCatStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph-elasticsearch["elasticgraph-elasticsearch"];
    elasticgraph-support["elasticgraph-support"];
    elasticsearch["elasticsearch"];
    faraday["faraday"];
    faraday-retry["faraday-retry"];
    elasticgraph-opensearch["elasticgraph-opensearch"];
    opensearch-ruby["opensearch-ruby"];
    elasticgraph-elasticsearch --> elasticgraph-support;
    elasticgraph-elasticsearch --> elasticsearch;
    elasticgraph-elasticsearch --> faraday;
    elasticgraph-elasticsearch --> faraday-retry;
    elasticgraph-opensearch --> elasticgraph-support;
    elasticgraph-opensearch --> faraday;
    elasticgraph-opensearch --> faraday-retry;
    elasticgraph-opensearch --> opensearch-ruby;
    class elasticgraph-elasticsearch targetGemStyle;
    class elasticgraph-support otherEgGemStyle;
    class elasticsearch externalGemCatStyle;
    class faraday externalGemCatStyle;
    class faraday-retry externalGemCatStyle;
    class elasticgraph-opensearch targetGemStyle;
    class opensearch-ruby externalGemCatStyle;
    click elasticsearch href "https://rubygems.org/gems/elasticsearch" "Open on RubyGems.org" _blank;
    click faraday href "https://rubygems.org/gems/faraday" "Open on RubyGems.org" _blank;
    click faraday-retry href "https://rubygems.org/gems/faraday-retry" "Open on RubyGems.org" _blank;
    click opensearch-ruby href "https://rubygems.org/gems/opensearch-ruby" "Open on RubyGems.org" _blank;
```

### Local Development Libraries (4 gems)

These libraries are used for local development of ElasticGraph applications, but are not intended to be deployed to production (except for `elasticgraph-rack`).
`elasticgraph-rack` is used to boot ElasticGraph locally but can also be used to run ElasticGraph in any rack-compatible server (including a Rails application).

* [elasticgraph](elasticgraph/README.md): Bootstraps ElasticGraph projects.
* [elasticgraph-local](elasticgraph-local/README.md): Provides support for developing and running ElasticGraph applications locally.
* [elasticgraph-rack](elasticgraph-rack/README.md): ElasticGraph gem for serving an ElasticGraph GraphQL endpoint using rack.
* [elasticgraph-schema_definition](elasticgraph-schema_definition/README.md): ElasticGraph gem that provides the schema definition API and generates schema artifacts.

#### Dependency Diagram

```mermaid
graph LR;
    classDef targetGemStyle fill:#FADBD8,stroke:#EC7063,color:#000,stroke-width:2px;
    classDef otherEgGemStyle fill:#A9DFBF,stroke:#2ECC71,color:#000;
    classDef externalGemCatStyle fill:#E0EFFF,stroke:#70A1D7,color:#2980B9;
    elasticgraph["elasticgraph"];
    elasticgraph-support["elasticgraph-support"];
    thor["thor"];
    elasticgraph-local["elasticgraph-local"];
    elasticgraph-admin["elasticgraph-admin"];
    elasticgraph-graphql["elasticgraph-graphql"];
    elasticgraph-indexer["elasticgraph-indexer"];
    elasticgraph-rack["elasticgraph-rack"];
    elasticgraph-schema_definition["elasticgraph-schema_definition"];
    rackup["rackup"];
    rake["rake"];
    webrick["webrick"];
    rack["rack"];
    elasticgraph-json_schema["elasticgraph-json_schema"];
    elasticgraph-schema_artifacts["elasticgraph-schema_artifacts"];
    graphql["graphql"];
    graphql-c_parser["graphql-c_parser"];
    elasticgraph --> elasticgraph-support;
    elasticgraph --> thor;
    elasticgraph-local --> elasticgraph-admin;
    elasticgraph-local --> elasticgraph-graphql;
    elasticgraph-local --> elasticgraph-indexer;
    elasticgraph-local --> elasticgraph-rack;
    elasticgraph-local --> elasticgraph-schema_definition;
    elasticgraph-local --> rackup;
    elasticgraph-local --> rake;
    elasticgraph-local --> webrick;
    elasticgraph-rack --> elasticgraph-graphql;
    elasticgraph-rack --> rack;
    elasticgraph-schema_definition --> elasticgraph-graphql;
    elasticgraph-schema_definition --> elasticgraph-indexer;
    elasticgraph-schema_definition --> elasticgraph-json_schema;
    elasticgraph-schema_definition --> elasticgraph-schema_artifacts;
    elasticgraph-schema_definition --> elasticgraph-support;
    elasticgraph-schema_definition --> graphql;
    elasticgraph-schema_definition --> graphql-c_parser;
    elasticgraph-schema_definition --> rake;
    class elasticgraph targetGemStyle;
    class elasticgraph-support otherEgGemStyle;
    class thor externalGemCatStyle;
    class elasticgraph-local targetGemStyle;
    class elasticgraph-admin otherEgGemStyle;
    class elasticgraph-graphql otherEgGemStyle;
    class elasticgraph-indexer otherEgGemStyle;
    class elasticgraph-rack targetGemStyle;
    class elasticgraph-schema_definition targetGemStyle;
    class rackup externalGemCatStyle;
    class rake externalGemCatStyle;
    class webrick externalGemCatStyle;
    class rack externalGemCatStyle;
    class elasticgraph-json_schema otherEgGemStyle;
    class elasticgraph-schema_artifacts otherEgGemStyle;
    class graphql externalGemCatStyle;
    class graphql-c_parser externalGemCatStyle;
    click thor href "https://rubygems.org/gems/thor" "Open on RubyGems.org" _blank;
    click rackup href "https://rubygems.org/gems/rackup" "Open on RubyGems.org" _blank;
    click rake href "https://rubygems.org/gems/rake" "Open on RubyGems.org" _blank;
    click webrick href "https://rubygems.org/gems/webrick" "Open on RubyGems.org" _blank;
    click rack href "https://rubygems.org/gems/rack" "Open on RubyGems.org" _blank;
    click graphql href "https://rubygems.org/gems/graphql" "Open on RubyGems.org" _blank;
    click graphql-c_parser href "https://rubygems.org/gems/graphql-c_parser" "Open on RubyGems.org" _blank;
```

