# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module ParallelSpecRunner
    def self.test_env_number
      @test_env_number ||= ENV.fetch("TEST_ENV_NUMBER")
    end

    def self.index_prefix
      @index_prefix ||= "test_env_#{test_env_number}_"
    end

    # Our various parallel spec runner adapters need to be hook into other classes in order to patch how they work to be compatible
    # with running concurrently at the same time as specs in another worker process. However, we support running our tests in multiple
    # ways, including in the context of a single gem's bundle. When running in a single gem's bundle, some dependencies may be unavailable
    # (it depends on what's in the gem's `gemspec` file). In that case, a require performed from one or more of these adapters may fail
    # with a `LoadError`. But that's OK: if a given dependency is not available, then it's not being used and we don't have to patch it!
    # So we can safely ignore it.
    #
    # But when we run from the repository root (i.e. in the context of the entire repo bundle) then we don't want to ignore these errors.
    def self.safe_require(file)
      require file
    rescue ::LoadError
      # :nocov: -- we don't get here when running the test suite for the entire repo
      raise if ::File.expand_path(::Dir.pwd) == ::File.expand_path(CommonSpecHelpers::REPO_ROOT)
      # :nocov:
    end

    safe_require "elastic_graph/spec_support/parallel_spec_runner/cluster_configuration_manager_adapter"
    safe_require "elastic_graph/spec_support/parallel_spec_runner/datastore_core_adapter"
    safe_require "elastic_graph/spec_support/parallel_spec_runner/datastore_spec_support_adapter"
    safe_require "elastic_graph/spec_support/parallel_spec_runner/elastic_graph_profiler_adapter"
    safe_require "elastic_graph/spec_support/parallel_spec_runner/request_tracker_request_adapter"

    ::Flatware.configure do |flatware|
      flatware.after_fork do
        # :nocov: -- which sides of these conditionals run depends on options used to run the test suite
        ::SimpleCov.at_fork.call(test_env_number) if defined?(::SimpleCov)

        unless ENV["NO_VCR"]
          require "elastic_graph/spec_support/vcr"
          VCR.configure do |config|
            # Use different cassette directories for different index prefixes--otherwise the HTTP requests to the datastore will have conflicting
            # index names and our tests will frequently need to re-run after deleting a cassette.
            config.cassette_library_dir += "/#{index_prefix.delete_suffix("_")}"
          end
        end
        # :nocov:
      end
    end

    module Overrides
      TEST_DOUBLE_REQUIRES_BY_CONSTANT_NAME = {
        "ElasticGraph::Elasticsearch::Client" => "elastic_graph/elasticsearch/client",
        "ElasticGraph::GraphQL::DatastoreQuery" => "elastic_graph/graphql/datastore_query",
        "ElasticGraph::GraphQL::DatastoreQuery::DocumentPaginator" => "elastic_graph/graphql/datastore_query",
        "ElasticGraph::GraphQL::DatastoreQuery::Paginator" => "elastic_graph/graphql/datastore_query",
        "ElasticGraph::GraphQL::DatastoreSearchRouter" => "elastic_graph/graphql/datastore_search_router",
        "ElasticGraph::SchemaArtifacts::FromDisk" => "elastic_graph/schema_artifacts/from_disk",
        "ElasticGraph::Support::MonotonicClock" => "elastic_graph/support/monotonic_clock",
        "GraphQL::Execution::Lookahead" => "graphql/execution/lookahead"
      }

      # Because `flatware` distributes the spec files across workers, we cannot count on doubled constants always being loaded when
      # we use the parallel spec runner. To ensure deterministic results, we're overriding `instance_double` here to make it load the
      # doubled constant so that RSpec doubled constant verification can proceed.
      def instance_double(constant, *args, **options)
        if constant.is_a?(String)
          file_to_require = TEST_DOUBLE_REQUIRES_BY_CONSTANT_NAME.fetch(constant) do
            # :nocov: -- only covered when there's a missing entry in `TEST_DOUBLE_REQUIRES_BY_CONSTANT_NAME`.
            fail "`instance_double` was called with `#{constant.inspect}`, but `TEST_DOUBLE_REQUIRES_BY_CONSTANT_NAME` " \
              "does not know what file to require for this. Please update `TEST_DOUBLE_REQUIRES_BY_CONSTANT_NAME` (in `#{__FILE__}`) " \
              "or use the direct constant instead of the string name of the constant."
            # :nocov:
          end

          require file_to_require
        end

        super
      end
    end
  end
end

RSpec.configure do |config|
  config.mock_with :rspec do |mocks|
    # Force `verify_doubled_constant_names` to `true`. This option checks our `instance_double` calls to ensure that the named
    # constant exists (because RSpec can't check our stubbed methods otherwise). We do not always set this option because it's
    # useful to be able to run a single unit test without loading a heavyweight dependency, and always setting this to true
    # would force us to always load dependencies that we use test doubles for.
    #
    # Usually, we only set this to true if there are any `acceptance` specs getting run--that's a signal that we're running end-to-end
    # tests and are running tests with everything loaded. However, when we're running parallel tests, we want to force it to `true`,
    # for a couple reasons:
    #
    # 1. This makes it deterministic. Our parallel test runner distributes the spec files across all workers based on the recorded runtimes
    #    of the specs (to try and balance them). This process is inherently non-deterministic, and can lead to "flickering" situations where
    #    a unit spec that uses `instance_double` is run with an acceptance spec on one run and not on the next run even though the entire
    #    suite is being run.
    # 2. We generally only use the parallel spec runner when running the entire suite (or at least the entire suite of a single gem), so
    #    we are already in a context when we're loading most or all things.
    mocks.verify_doubled_constant_names = true
  end

  config.prepend ElasticGraph::ParallelSpecRunner::Overrides
end
