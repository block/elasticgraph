ARG RUBY_VERSION
FROM ruby:${RUBY_VERSION}

ARG TARGET_APOLLO_FEDERATION_VERSION

WORKDIR /web

# Each of the elasticgraph gems this implementation depends on must be
# copied into the container so it's available for inclusion in the bundle.
COPY elasticgraph-admin /web/elasticgraph-admin
COPY elasticgraph-apollo /web/elasticgraph-apollo
COPY elasticgraph-datastore_core /web/elasticgraph-datastore_core
COPY elasticgraph-elasticsearch /web/elasticgraph-elasticsearch
COPY elasticgraph-graphiql /web/elasticgraph-graphiql
COPY elasticgraph-graphql /web/elasticgraph-graphql
COPY elasticgraph-indexer /web/elasticgraph-indexer
COPY elasticgraph-rack /web/elasticgraph-rack
COPY elasticgraph-schema_artifacts /web/elasticgraph-schema_artifacts
COPY elasticgraph-schema_definition /web/elasticgraph-schema_definition
COPY elasticgraph-support /web/elasticgraph-support

# We also have to copy the implementation files (config, schema, etc) as well.
COPY elasticgraph-apollo/apollo_tests_implementation /web/

# We need to install the bundle and generate our schema artifacts.
RUN bundle install
RUN bundle exec rake schema_artifacts:dump TARGET_APOLLO_FEDERATION_VERSION=${TARGET_APOLLO_FEDERATION_VERSION}

# Finally we can boot the app!
CMD ["bundle", "exec", "rackup", "--host", "0.0.0.0", "--port", "4001"]
