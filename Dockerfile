# Use Ruby 3.x as the base image
FROM ruby:3.4

ENV PORT=9393

# Set working directory
WORKDIR /app

# Copy the entire project
COPY . .


# Retain just the files needed for building
RUN find . \! -name "Gemfile" \! -name "*.gemspec" -mindepth 2 -maxdepth 2 -print | xargs rm -rf
RUN find . \! -name "Gemfile*" \! -name "*.gemspec"  -maxdepth 1 -type f | xargs rm

# Also need the version file add it back
COPY elasticgraph-support/lib/elastic_graph/version.rb ./elasticgraph-support/lib/elastic_graph/version.rb


# Use Ruby 3.x as the base image
FROM ruby:3.4

WORKDIR /app


# Copy files from the first build stage.
COPY --from=0 /app .

# Install Ruby dependencies
RUN bundle install

# Copy the entire project
COPY . .


CMD ["bundle", "exec", "rake", "boot_in_container[${PORT,--host=0.0.0.0,true]"]
