# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file exists to enable simplecov for any of the ElasticGraph gems. To use it, set a `COVERAGE` env var:
#
# COVERAGE=1 be rspec path/to/gem/spec
require "simplecov"
require "simplecov-console"

module ElasticGraph
  class FailedCoverageRequirementFormatter
    def format(result)
      return if result.missed_lines == 0 && result.missed_branches == 0

      puts <<~EOS

        #{"=" * 100}
        Your test run had #{result.missed_lines} lines and #{result.missed_branches} code branches that were not covered by the executed tests.
        We do not have a goal of 100% test coverage in ElasticGraph; however, we do have the goal of having
        all uncovered code explicitly labeled as such with `# :nocov:` so that it is easy to tell at a
        glance what code is uncovered by tests. And we do want a high level of test coverage; Ruby's dynamic
        nature means that misspelled variables, method names, etc can usually only be detected at run time, meaning
        that every uncovered line of code is a line that our CI build may not be able to detect a breakage in.

        See the table above to see detailed coverage information.  For each bit of uncovered code, do one of the following:

        1) Delete it. If the code is "dead code" (such as a private method that no longer has any callers),
           just delete it!

        2) Add test coverage. (This might require refactoring the code to make it more testable).

        3) Surround the code with `# :nocov:` comments (on the lines before and after) to mark it as a known
           uncovered bit of code. This should only be done for code that you have determined would cost more
           to test than the value we would get from the tests. For example, this is sometimes the case for
           code that only ever runs locally (e.g. in a rake task) that interacts heavily with the environment.
           Note: if you add a `# :nocov:` comment, please leave an explanation for why the code is not being
           covered.
        #{"=" * 100}

      EOS
    end
  end

  if defined?(::Flatware)
    module SimpleCovPatches
      attr_accessor :flatware_main_process_pid

      def wait_for_other_processes
        # There's a race condition with SimpleCov and a parallel runner like flatware:
        # the final worker process often hasn't written its results when we get here, and
        # we need to sleep a bit to give it time to finish.
        sleep 1 if flatware_main_process_pid == ::Process.pid
        super
      end
    end
    ::SimpleCov.singleton_class.prepend SimpleCovPatches

    ::Flatware.configure do |conf|
      # Record the pid of the main process (the one that spawns the workers, and that SimpleCov prints results from).
      conf.before_fork { ::SimpleCov.flatware_main_process_pid = ::Process.pid }
    end
  end
end

# Identify if we are running a single gem's specs; if so we will only check coverage of that one gem.
spec_files_to_run = RSpec.configuration.files_to_run
gems_being_tested_dirs = spec_files_to_run
  .filter_map { |f| Pathname(f).ascend.find { |p| p.glob("*.gemspec").any? } }
  .uniq

gem_dir = gems_being_tested_dirs.first if gems_being_tested_dirs.one?
repo_root = File.expand_path("../../../..", __dir__)
tmp_coverage_dir = "#{repo_root}/tmp/coverage"

# Don't allow results from a prior run to "contaminate" the current run.
FileUtils.rm_rf(tmp_coverage_dir)

SimpleCov.enable_for_subprocesses(true)

SimpleCov.start do
  if gems_being_tested_dirs.one?
    gem_dir = gems_being_tested_dirs.first
    root gem_dir.to_s
    command_name gem_dir.basename.to_s
  else
    root repo_root
    command_name "elasticgraph"
  end

  coverage_dir tmp_coverage_dir

  add_filter "/bundle"

  add_filter "/elastic_graph/project_template/"

  # When we use `script/run_specs` we avoid running the `elasticgraph-local` specs, but some of the
  # elasticgraph-local code gets loaded and used as a dependency. We don't want to consider its coverage
  # status if we're not running it's test suite.
  add_filter "/elasticgraph-local/" unless spec_files_to_run.any? { |f| f.include?("/elasticgraph-local/") }

  # This version file is loaded from our gemspecs, which can get loaded by bundler before we get here.
  # SimpleCov is only able to track coverage of files loaded after it starts, so we need to filter them out if
  # their constant is already defined. They don't contain any branching statements or anything so it's ok to
  # ignore them here.
  add_filter "lib/elastic_graph/version.rb" if defined?(::ElasticGraph::VERSION)

  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::Console,
    ElasticGraph::FailedCoverageRequirementFormatter
  ])

  gems_being_tested_globs = gems_being_tested_dirs.flat_map { |dir| [dir / "lib/**/*.rb", dir / "spec/**/*.rb"] }
  track_files "{#{gems_being_tested_globs.join(",")}}"

  enable_coverage :branch
  minimum_coverage line: 100, branch: 100

  merge_timeout 1800 # 30 minutes. CI jobs can take 15-20 minutes.
end
