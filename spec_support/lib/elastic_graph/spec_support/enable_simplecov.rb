# Copyright 2024 - 2026 Block, Inc.
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

  # SimpleCov backfills `track_files`-matched files that a process never loaded with simulated
  # coverage based on `Coverage.line_stub`. On affected CRuby versions (see below),
  # `Coverage.line_stub` classifies a few lines (e.g. continuation lines of multi-line hash
  # literals, and `in` clauses of `case`/`in` expressions) as relevant-but-uncovered (`0`) even
  # though the runtime `Coverage` API classifies them as not relevant (`nil`) when the file is
  # actually loaded. When such a simulated result (e.g. from the flatware main process, which runs
  # no tests) merges with a real result, SimpleCov 1.x treats "relevant on either side" as
  # relevant, so the phantom `0` survives the merge and the file misleadingly reports < 100%
  # coverage. On affected Ruby versions, we restore SimpleCov 0.22's merge semantics: an unexecuted
  # (`0`) line only counts as relevant if BOTH sides agree it is relevant. Genuinely unloaded files
  # are unaffected--all of their merged values are `0`-vs-`0`, which still merges to `0`--and
  # executed lines are unaffected (`nil`-vs-positive still merges to the positive count).
  #
  # Affected versions (verified with a `Coverage.line_stub`-vs-runtime probe against docker
  # ruby-slim images): 3.4.1 through 4.0.3; 3.4.0 and 4.0.4 are clean, and no 3.4.x has the fix
  # backported as of 3.4.7. On 3.4.x the mismatch shows up for multi-line all-static hash literals
  # in files with a `# frozen_string_literal: true` magic comment (i.e. every file in this repo):
  # the literal is compile-time folded so its continuation lines fire no runtime line events, but
  # `Coverage.line_stub` still marks them relevant. On 4.0.0-4.0.3 the same happens without the
  # magic comment. If a future 3.4.x release ships the backported fix, this range will over-apply
  # to it, which is harmless; tighten the range at that point to keep the gate meaningful.
  #
  # :nocov: -- which branch executes depends on the Ruby version.
  affected_versions = ::Gem::Version.new("3.4.1")...::Gem::Version.new("4.0.4")
  if ::RUBY_ENGINE == "ruby" && affected_versions.cover?(::Gem::Version.new(::RUBY_VERSION))
    module LinesCombinerPatch
      def merge_line_coverage(first_val, second_val)
        return nil if (first_val.nil? || second_val.nil?) && first_val.to_i + second_val.to_i == 0
        super
      end
    end
    ::SimpleCov::Combine::LinesCombiner.singleton_class.prepend LinesCombinerPatch
  end
  # :nocov:

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

  # Don't track coverage of JRuby patch files as we only enforce coverage on MRI..
  add_filter "jruby_patches"

  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::Console,
    ElasticGraph::FailedCoverageRequirementFormatter
  ])

  gems_being_tested_globs = gems_being_tested_dirs.flat_map { |dir| [dir / "lib/**/*.rb", dir / "spec/**/*.rb"] }
  # An empty pattern here (e.g. when running specs that aren't under any gem's directory, like `config/linting`)
  # causes simplecov 1.x to attempt to read the repo root directory as a file, raising `Errno::EISDIR`.
  track_files "{#{gems_being_tested_globs.join(",")}}" unless gems_being_tested_globs.empty?

  enable_coverage :branch
  minimum_coverage line: 100, branch: 100

  merge_timeout 1800 # 30 minutes. CI jobs can take 15-20 minutes.
end
