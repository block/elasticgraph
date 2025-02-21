# Use Ruby 3.x as the base image
FROM ruby:3.2

# Set working directory
WORKDIR /app

# Install system dependencies and clean up in a single layer
RUN mkdir -p ~/.gnupg && \
    chmod 700 ~/.gnupg && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
    build-essential \
    git \
    nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p log tmp

# Copy the Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock ./
COPY Gemfile-custom.example Gemfile-custom

# Install Ruby dependencies
RUN bundle install

# Copy the entire project
COPY . .

# Set the default command to run the application
CMD ["bundle", "exec", "rake", "boot_locally"]