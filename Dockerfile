ARG PORT=9393
ARG RUBY_VERSION=3.4

# Use Ruby 3.x as the base image
FROM ruby:${RUBY_VERSION}

# Set working directory
WORKDIR /app

# Copy the entire project
COPY . .


# Retain just the files needed for building
RUN find . \! -name "Gemfile" \! -name "*.gemspec" -mindepth 2 -maxdepth 2 -print | xargs rm -rf
RUN find . \! -name "Gemfile*" \! -name "*.gemspec"  -maxdepth 1 -type f | xargs rm

# Also need the version file. add it back
COPY elasticgraph-support/lib/elastic_graph/version.rb ./elasticgraph-support/lib/elastic_graph/version.rb


# Use Ruby 3.x as the base image
FROM ruby:${RUBY_VERSION}

WORKDIR /app/elasticgraph


# Copy files from the first build stage.
COPY --from=0 /app .

# Install Ruby dependencies
RUN bundle install

# Copy the entire project
COPY . .

# Running the new command will commit to git. Setup defaults
RUN git config --global user.email "test@example.com"
RUN git config --global user.name "Demo User"

# Use the elasticgraph gem local to the container
RUN sed -i 's|"#{VERSION}"|path: \"/app/elasticgraph\"|g' elasticgraph/lib/elastic_graph/cli.rb


# Why does this need to run a second time?
RUN bundle install

WORKDIR /app

# Create demo app using the locally build elasticgraph project
RUN BUNDLE_GEMFILE=/app/elasticgraph/Gemfile bundle exec elasticgraph new demo


# Change work directory into the demo app
WORKDIR /app/demo

# Reference OpenSearch from the docker container
RUN sed -i 's/localhost:9293/opensearch:9200/g' config/settings/local.yaml


# Generate fake data and boot the graphiql api
CMD ["bundle", "exec", "rake", "index_fake_data:artists" ,"boot_graphiql[${PORT},--host=0.0.0.0,true]"]
