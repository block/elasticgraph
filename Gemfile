# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

source "https://rubygems.org"

# Gems needed by the test suite and other CI checks.
group :development do
  gem "aws_lambda_ric", "~> 3.0"
  gem "coderay", "~> 1.1", ">= 1.1.3"
  gem "factory_bot", "~> 6.5", ">= 6.5.1"
  gem "faker", "~> 3.5", ">= 3.5.1"
  gem "flatware-rspec", "~> 2.3", ">= 2.3.4"
  gem "httpx", "~> 1.4", ">= 1.4.1"
  gem "method_source", "~> 1.1"
  gem "rubocop-factory_bot", "~> 2.26", ">= 2.26.1"
  gem "rubocop-rake", "~> 0.6"
  gem "rubocop-rspec", "~> 3.4"
  gem "rspec", "~> 3.13"
  gem "rspec-retry", "~> 0.6", ">= 0.6.2"
  gem "simplecov", "~> 0.22"
  gem "simplecov-console", "~> 0.9", ">= 0.9.3"
  gem "standard", "~> 1.45.0"
  gem "steep", "~> 1.9.4"
  gem "super_diff", "~> 0.15"
  gem "vcr", "~> 6.3", ">= 6.3.1"
end

# Documentation generation gems
group :site do
  gem "filewatcher", "~> 2.1"
  gem "html-proofer", "~> 5.0", ">= 5.0.10"
  gem "jekyll", "~> 4.4", ">= 4.4.1"
  gem "nokogiri", "~> 1.18", ">= 1.18.4"
  gem "yard", "~> 0.9", ">= 0.9.37"
  gem "yard-doctest", "~> 0.1", ">= 0.1.17"
end

# Since this file gets symlinked both at the repo root and into each Gem directory, we have
# to dynamically detect the repo root, by looking for one of the subdirs at the root.
repo_root = ::Pathname.new(__dir__).ascend.find { |dir| ::Dir.exist?("#{dir}/elasticgraph-support") }.to_s

# `tmp` and `log` are git-ignored but many of our build tasks and scripts expect them to exist.
# We create them here since `Gemfile` evaluation happens before anything else.
require "fileutils"
::FileUtils.mkdir_p("#{repo_root}/log")
::FileUtils.mkdir_p("#{repo_root}/tmp")

# Identify the gems that live in the ElasticGraph repository.
gems_in_this_repo = ::Dir.glob("#{repo_root}/*/*.gemspec").map do |gemspec|
  ::File.basename(::File.dirname(gemspec))
end.to_set

# Here we override the `gem` method to automatically add the ElasticGraph version
# to all ElasticGraph gems. If we don't do this, we can get confusing bundler warnings
# like:
#
# A gemspec development dependency (elasticgraph-schema_definition, = 0.17.1.0) is being overridden by a Gemfile dependency (elasticgraph-schema_definition, >= 0).
# This behaviour may change in the future. Please remove either of them, or make sure they both have the same requirement
#
# This is necessary because our `gemspec` call below registers a `gem` for the gem defined by the gemspec, but it does not include
# a version requirement, and bundler gets confused when other gems have dependencies on the same gem with a version requirement.
# This ensures that we always have the same version requirements for all ElasticGraph gems.
define_singleton_method :gem do |name, *args|
  if gems_in_this_repo.include?(name)
    args.unshift ::ElasticGraph::VERSION unless args.first.include?(::ElasticGraph::VERSION)
  end

  super(name, *args)
end

# This file is symlinked from the repo root into each gem directory. To detect which case we're in,
# we can compare the the current directory to the repo root.
if repo_root == __dir__
  # When we are at the root, we want to load the gemspecs for each ElasticGraph gem in the repository.
  # Note: dependabot can't handle `gemspec` calls that use a variable (e.g. `gemspec path: gem_name`)
  # rather than a literal value, so this is an intentionally unrolled loop.
  gemspec path: "elasticgraph"
  gemspec path: "elasticgraph-admin"
  gemspec path: "elasticgraph-admin_lambda"
  gemspec path: "elasticgraph-apollo"
  gemspec path: "elasticgraph-datastore_core"
  gemspec path: "elasticgraph-elasticsearch"
  gemspec path: "elasticgraph-graphql"
  gemspec path: "elasticgraph-graphql_lambda"
  gemspec path: "elasticgraph-health_check"
  gemspec path: "elasticgraph-indexer"
  gemspec path: "elasticgraph-indexer_autoscaler_lambda"
  gemspec path: "elasticgraph-indexer_lambda"
  gemspec path: "elasticgraph-json_schema"
  gemspec path: "elasticgraph-lambda_support"
  gemspec path: "elasticgraph-local"
  gemspec path: "elasticgraph-opensearch"
  gemspec path: "elasticgraph-query_interceptor"
  gemspec path: "elasticgraph-query_registry"
  gemspec path: "elasticgraph-rack"
  gemspec path: "elasticgraph-schema_artifacts"
  gemspec path: "elasticgraph-schema_definition"
  gemspec path: "elasticgraph-support"

  unless @gemspecs.empty?
    missing_gemspecs = gems_in_this_repo - @gemspecs.map(&:name)
    unless missing_gemspecs.empty?
      raise "`Gemfile` is missing `gemspec` calls for gems: #{missing_gemspecs.join(", ")}"
    end
  end
else
  # Otherwise, we just load the local `.gemspec` file in the current directory.
  gemspec

  # After loading the gemspec, we want to explicitly tell bundler where to find each of the ElasticGraph
  # gems that live in this repository. Otherwise, it will try to look in system gems or on a remote
  # gemserver for them.
  #
  # Bundler stores all loaded gemspecs in `@gemspecs` so here we get the gemspec that was just loaded
  if (loaded_gemspec = @gemspecs.last)

    # This set will keep track of which gems have been registered so far, so we never register an
    # ElasticGraph gem more than once.
    registered_gems = ::Set.new

    register_gemspec_gems_with_path = lambda do |deps|
      deps.each do |dep|
        next unless gems_in_this_repo.include?(dep.name) && !registered_gems.include?(dep.name)

        dep_path = "#{repo_root}/#{dep.name}"
        gem dep.name, path: dep_path

        # record the fact that this gem has been registered so that we don't try calling `gem` for it again.
        registered_gems << dep.name

        # Finally, load the gemspec and recursively apply this process to its runtime dependencies.
        # Notably, we avoid using `.dependencies` because we do not want development dependencies to
        # be registered as part of this.
        runtime_dependencies = ::Bundler.load_gemspec("#{dep_path}/#{dep.name}.gemspec").runtime_dependencies
        register_gemspec_gems_with_path.call(runtime_dependencies)
      end
    end

    # Ensure that the recursive lambda above doesn't try to re-register the loaded gemspec's gem.
    registered_gems << loaded_gemspec.name

    # Here we begin the process of registering the ElasticGraph gems we need to include in the current
    # bundle. We use `loaded_gemspec.dependencies` to include development and runtime dependencies.
    # For the "outer" gem identified by our loaded gemspec, we need the bundle to include both its
    # runtime and development dependencies. In contrast, when we recurse, we only look at runtime
    # dependencies. We are ok with transitive runtime dependencies being pulled in but we don't want
    # transitive development dependencies.
    register_gemspec_gems_with_path.call(loaded_gemspec.dependencies)
  end
end
