ARG PORT=9393
ARG RUBY_VERSION=3.4

FROM ruby:${RUBY_VERSION}

WORKDIR /app

# Copy the minimal Gemfile and local ElasticGraph gems that we need.
COPY config/docker_demo/Gemfile .
COPY elasticgraph elasticgraph
COPY elasticgraph-admin elasticgraph-admin
COPY elasticgraph-datastore_core elasticgraph-datastore_core
COPY elasticgraph-graphql elasticgraph-graphql
COPY elasticgraph-indexer elasticgraph-indexer
COPY elasticgraph-json_schema elasticgraph-json_schema
COPY elasticgraph-local elasticgraph-local
COPY elasticgraph-opensearch elasticgraph-opensearch
COPY elasticgraph-query_registry elasticgraph-query_registry
COPY elasticgraph-rack elasticgraph-rack
COPY elasticgraph-schema_artifacts elasticgraph-schema_artifacts
COPY elasticgraph-schema_definition elasticgraph-schema_definition
COPY elasticgraph-support elasticgraph-support

# Change the `ElasticGraph::VERSION` constant to a version that will never match any of the released
# ElasticGraph gems. This ensures that when we `bundle install` in our demo project, it will not fall
# back to released ElasticGraph gems. If we've failed to copy over any of the ElasticGraph gems needed
# to boot the demo app, we want it to fail fast and tell us rather than pulling in released gems.
RUN sed -i 's/^\(\s*\)VERSION = ".*"/\1VERSION = "999.999.999"/' elasticgraph-support/lib/elastic_graph/version.rb

# Install dependencies
RUN bundle install

# Running the new command will commit to git. Setup defaults
RUN git config --global user.email "test@example.com"
RUN git config --global user.name "Demo User"

# Create demo app using the locally built elasticgraph project
RUN ELASTICGRAPH_GEMS_PATH=/app bundle exec elasticgraph new demo --datastore opensearch

# Change work directory into the demo app
WORKDIR /app/demo

# Reference OpenSearch from the docker container
RUN sed -i 's/localhost:9293/opensearch:9200/g' config/settings/local.yaml

# Generate fake data and boot the GraphiQL UI
CMD ["bundle", "exec", "rake", "index_fake_data:artists" ,"boot_graphiql[${PORT},--host=0.0.0.0,true]"]
