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
    elasticgraph-admin --> elasticgraph-datastore_core & elasticgraph-indexer & elasticgraph-schema_artifacts & elasticgraph-support & rake
    elasticgraph-datastore_core --> elasticgraph-schema_artifacts & elasticgraph-support
    elasticgraph-graphql --> base64 & elasticgraph-datastore_core & elasticgraph-schema_artifacts & graphql & graphql-c_parser
    elasticgraph-indexer --> elasticgraph-datastore_core & elasticgraph-json_schema & elasticgraph-schema_artifacts & elasticgraph-support & hashdiff
    elasticgraph-json_schema --> elasticgraph-support & json_schemer
    elasticgraph-schema_artifacts --> elasticgraph-support
    elasticgraph-support --> logger
    style elasticgraph-admin color: DodgerBlue;
    style elasticgraph-datastore_core color: DodgerBlue;
    style elasticgraph-graphql color: DodgerBlue;
    style elasticgraph-indexer color: DodgerBlue;
    style elasticgraph-json_schema color: DodgerBlue;
    style elasticgraph-schema_artifacts color: DodgerBlue;
    style elasticgraph-support color: DodgerBlue;
    style rake color: Red;
    style base64 color: Red;
    style graphql color: Red;
    style graphql-c_parser color: Red;
    style hashdiff color: Red;
    style json_schemer color: Red;
    style logger color: Red;
click base64 href "https://rubygems.org/gems/base64"
click graphql href "https://rubygems.org/gems/graphql"
click graphql-c_parser href "https://rubygems.org/gems/graphql-c_parser"
click hashdiff href "https://rubygems.org/gems/hashdiff"
click json_schemer href "https://rubygems.org/gems/json_schemer"
click logger href "https://rubygems.org/gems/logger"
click rake href "https://rubygems.org/gems/rake"
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
    elasticgraph-admin_lambda --> rake & elasticgraph-admin & elasticgraph-lambda_support
    elasticgraph-graphql_lambda --> elasticgraph-graphql & elasticgraph-lambda_support
    elasticgraph-indexer_autoscaler_lambda --> elasticgraph-datastore_core & elasticgraph-lambda_support & aws-sdk-lambda & aws-sdk-sqs & aws-sdk-cloudwatch & ox
    elasticgraph-indexer_lambda --> elasticgraph-indexer & elasticgraph-lambda_support & aws-sdk-s3 & ox
    elasticgraph-lambda_support --> elasticgraph-opensearch & faraday_middleware-aws-sigv4
    style elasticgraph-admin_lambda color: DodgerBlue;
    style elasticgraph-graphql_lambda color: DodgerBlue;
    style elasticgraph-indexer_autoscaler_lambda color: DodgerBlue;
    style elasticgraph-indexer_lambda color: DodgerBlue;
    style elasticgraph-lambda_support color: DodgerBlue;
    style rake color: Red;
    style elasticgraph-admin color: Green;
    style elasticgraph-graphql color: Green;
    style elasticgraph-datastore_core color: Green;
    style aws-sdk-lambda color: Red;
    style aws-sdk-sqs color: Red;
    style aws-sdk-cloudwatch color: Red;
    style ox color: Red;
    style elasticgraph-indexer color: Green;
    style aws-sdk-s3 color: Red;
    style elasticgraph-opensearch color: Green;
    style faraday_middleware-aws-sigv4 color: Red;
click aws-sdk-cloudwatch href "https://rubygems.org/gems/aws-sdk-cloudwatch"
click aws-sdk-lambda href "https://rubygems.org/gems/aws-sdk-lambda"
click aws-sdk-s3 href "https://rubygems.org/gems/aws-sdk-s3"
click aws-sdk-sqs href "https://rubygems.org/gems/aws-sdk-sqs"
click faraday_middleware-aws-sigv4 href "https://rubygems.org/gems/faraday_middleware-aws-sigv4"
click ox href "https://rubygems.org/gems/ox"
click rake href "https://rubygems.org/gems/rake"
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
    elasticgraph-apollo --> elasticgraph-graphql & elasticgraph-support & graphql & apollo-federation
    elasticgraph-health_check --> elasticgraph-datastore_core & elasticgraph-graphql & elasticgraph-support
    elasticgraph-query_interceptor --> elasticgraph-graphql & elasticgraph-schema_artifacts
    elasticgraph-query_registry --> elasticgraph-graphql & elasticgraph-support & graphql & graphql-c_parser & rake
    style elasticgraph-apollo color: DodgerBlue;
    style elasticgraph-health_check color: DodgerBlue;
    style elasticgraph-query_interceptor color: DodgerBlue;
    style elasticgraph-query_registry color: DodgerBlue;
    style elasticgraph-graphql color: Green;
    style elasticgraph-support color: Green;
    style graphql color: Red;
    style apollo-federation color: Red;
    style elasticgraph-datastore_core color: Green;
    style elasticgraph-schema_artifacts color: Green;
    style graphql-c_parser color: Red;
    style rake color: Red;
click apollo-federation href "https://rubygems.org/gems/apollo-federation"
click graphql href "https://rubygems.org/gems/graphql"
click graphql-c_parser href "https://rubygems.org/gems/graphql-c_parser"
click rake href "https://rubygems.org/gems/rake"
```

### Datastore Adapters (2 gems)

These libraries adapt ElasticGraph to your choice of datastore (Elasticsearch or OpenSearch).

* [elasticgraph-elasticsearch](elasticgraph-elasticsearch/README.md): Wraps the Elasticsearch client for use by ElasticGraph.
* [elasticgraph-opensearch](elasticgraph-opensearch/README.md): Wraps the OpenSearch client for use by ElasticGraph.

#### Dependency Diagram

```mermaid
graph LR;
    elasticgraph-elasticsearch --> elasticgraph-support & elasticsearch & faraday & faraday-retry
    elasticgraph-opensearch --> elasticgraph-support & faraday & faraday-retry & opensearch-ruby
    style elasticgraph-elasticsearch color: DodgerBlue;
    style elasticgraph-opensearch color: DodgerBlue;
    style elasticgraph-support color: Green;
    style elasticsearch color: Red;
    style faraday color: Red;
    style faraday-retry color: Red;
    style opensearch-ruby color: Red;
click elasticsearch href "https://rubygems.org/gems/elasticsearch"
click faraday href "https://rubygems.org/gems/faraday"
click faraday-retry href "https://rubygems.org/gems/faraday-retry"
click opensearch-ruby href "https://rubygems.org/gems/opensearch-ruby"
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
    elasticgraph --> elasticgraph-support & thor
    elasticgraph-local --> elasticgraph-admin & elasticgraph-graphql & elasticgraph-indexer & elasticgraph-rack & elasticgraph-schema_definition & rackup & rake & webrick
    elasticgraph-rack --> elasticgraph-graphql & rack
    elasticgraph-schema_definition --> elasticgraph-graphql & elasticgraph-indexer & elasticgraph-json_schema & elasticgraph-schema_artifacts & elasticgraph-support & graphql & graphql-c_parser & rake
    style elasticgraph color: DodgerBlue;
    style elasticgraph-local color: DodgerBlue;
    style elasticgraph-rack color: DodgerBlue;
    style elasticgraph-schema_definition color: DodgerBlue;
    style elasticgraph-support color: Green;
    style thor color: Red;
    style elasticgraph-admin color: Green;
    style elasticgraph-graphql color: Green;
    style elasticgraph-indexer color: Green;
    style rackup color: Red;
    style rake color: Red;
    style webrick color: Red;
    style rack color: Red;
    style elasticgraph-json_schema color: Green;
    style elasticgraph-schema_artifacts color: Green;
    style graphql color: Red;
    style graphql-c_parser color: Red;
click graphql href "https://rubygems.org/gems/graphql"
click graphql-c_parser href "https://rubygems.org/gems/graphql-c_parser"
click rack href "https://rubygems.org/gems/rack"
click rackup href "https://rubygems.org/gems/rackup"
click rake href "https://rubygems.org/gems/rake"
click thor href "https://rubygems.org/gems/thor"
click webrick href "https://rubygems.org/gems/webrick"
```

