ARG PORT=9000
ARG RUBY_VERSION=3.4

FROM ruby:${RUBY_VERSION} AS builder

WORKDIR /app

# Copy all files needed for the build
COPY config/docker_demo/Gemfile \
     elasticgraph-support/lib/elastic_graph/version.rb \
     ./
COPY elasticgraph elasticgraph/
COPY elasticgraph-support elasticgraph-support/
COPY elasticgraph-admin elasticgraph-admin/
COPY elasticgraph-datastore_core elasticgraph-datastore_core/
COPY elasticgraph-graphiql elasticgraph-graphiql/
COPY elasticgraph-graphql elasticgraph-graphql/
COPY elasticgraph-indexer elasticgraph-indexer/
COPY elasticgraph-local elasticgraph-local/
COPY elasticgraph-opensearch elasticgraph-opensearch/
COPY elasticgraph-query_registry elasticgraph-query_registry/
COPY elasticgraph-rack elasticgraph-rack/
COPY elasticgraph-schema_artifacts elasticgraph-schema_artifacts/
COPY elasticgraph-schema_definition elasticgraph-schema_definition/

# Set up git, install dependencies, and create demo app all in one layer
RUN <<EOS
  set -e
  # Avoid "fatal: not a git repository (or any of the parent directories): .git"
  git init

  # Running the `elasticgraph new` command will commit to git. Setup defaults.
  git config --global user.email "test@example.com"
  git config --global user.name "Demo User"

  # Add all files to git so we can generate file lists
  git add .
  git commit -m "Initial commit"

  # Pre-generate file lists for all gems
  for gem in elasticgraph*; do
    if [ -d "$gem" ]; then
      cd "$gem"
      git ls-files -z > .files_list
      cd ..
    fi
  done

  # Change the `ElasticGraph::VERSION` constant to a version that will never match any of the released
  # ElasticGraph gems. This ensures that when we `bundle install` in our demo project, it will not fall
  # back to released ElasticGraph gems. If we've failed to copy over any of the ElasticGraph gems needed
  # to boot the demo app, we want it to fail fast and tell us rather than pulling in released gems.
  sed -i 's/^\(\s*\)VERSION = ".*"/\1VERSION = "999.999.999"/' elasticgraph-support/lib/elastic_graph/version.rb

  # Install dependencies
  bundle install

  # Create demo app
  ELASTICGRAPH_GEMS_PATH=/app bundle exec elasticgraph new demo --datastore opensearch

  # Configure OpenSearch connection
  sed -i 's/localhost/opensearch/g' demo/config/settings/local.yaml

  # Clean up unnecessary files
  rm -rf .git
  rm -rf /usr/local/bundle/cache
  find . -type d -name 'spec' -exec rm -rf {} +
  find . -type d -name 'sig' -exec rm -rf {} +
EOS

# Use intermediary stage to copy over everything needed.
FROM ruby:${RUBY_VERSION}-slim AS organizer

WORKDIR /app

# Copy the installed gems and demo app first
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder /app/demo /app

# Copy all ElasticGraph gems in a single layer
RUN --mount=from=builder,source=/app,target=/builder \
    cp -r /builder/elasticgraph* .

# Patch gemspecs to use pre-generated file lists
RUN <<EOS
  set -e
  for gem in elasticgraph*; do
    if [ -d "$gem" ]; then
      sed -i 's/`git ls-files -z`/File.read(".files_list")/' "$gem"/*.gemspec
    fi
  done
EOS

# Final stage with single layer
FROM ruby:${RUBY_VERSION}-slim

WORKDIR /app

# Copy everything in a single layer
COPY --from=organizer / /

# Generate fake data and boot the GraphiQL UI
CMD ["bundle", "exec", "rake", "index_fake_data:artists", "boot_graphiql[${PORT}, --host=0.0.0.0, true]"]
