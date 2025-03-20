# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "stringio"
require "rake"

module ElasticGraph
  module RakeTaskSupport
    # Runs rake with the given CLI args, returning the string output of running rake.
    # The caller should pass a block that defines the tasks (using the provided `output` object).
    def run_rake(*cli_args)
      output = StringIO.new

      rake_app = ::Rake::Application.new

      # Rake truncates output when it detects a TTY output, and the truncation is dynamic
      # based on the detected width of the terminal. To prevent a narrow terminal from causing
      # test failures, we set this to disable truncation.
      rake_app.tty_output = false

      # Stop Rake from attempting to load a rakefile. Instead, when we yield the caller will define the tasks
      # by instantiating a class that inherits from `Rake::TaskLib`.
      def rake_app.load_rakefile
      end

      rake_app.options.trace_output = output

      # Neutralize the standard exception handling. Otherwise an exception (which we want to allow to be propagated into
      # the test itself) can cause Rake to call `exit` and end the Ruby process.
      def rake_app.standard_exception_handling
        yield
      end

      # Ensure any print done by the rake application goes to `output`.
      rake_app.define_singleton_method(:printf) do |*args, **options, &block|
        output.printf(*args, **options, &block)
      end

      # The `--dry-run` flag mutates some global Rake state. Here we restore that state to its original values.
      # Otherwise, a test running with `--dry-run` can impact later tests that run.
      ::Rake.nowrite(RakeTaskSupport.rake_orig_nowrite)
      ::Rake.verbose(RakeTaskSupport.rake_orig_verbose)

      ::Rake.with_application(rake_app) do
        # Necessary so that testing `--tasks` works.
        ::Rake::TaskManager.record_task_metadata = true

        yield output # to define the tasks. Caller should inject `output` in their rake task definitions.
        rake_app.run(cli_args)
      end

      output.string
    end

    class << self
      attr_reader :rake_orig_nowrite, :rake_orig_verbose
    end

    @rake_orig_nowrite = ::Rake.nowrite
    @rake_orig_verbose = ::Rake.verbose
  end
end

RSpec.configure do |c|
  c.include ElasticGraph::RakeTaskSupport, :rake_task
end
