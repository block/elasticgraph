# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "rake"
require "tempfile"

module ElasticGraph
  module AdminLambda
    # @private
    class RakeAdapter
      RAKEFILE = File.expand_path("../Rakefile", __FILE__)

      def self.run_rake(argv)
        capture_output do
          # We need to instantiate a new application on each invocation, because Rake is normally
          # designed to run once and exit. It keeps track of tasks that have already run and will
          # no-op when you try to run a task a 2nd or 3rd time. Using a new application instance
          # each time avoids this issue.
          ::Rake.with_application(Application.new) do |application|
            application.run(argv)
          end
        end
      end

      # Captures stdout/stderr into a string so we can return it from the lambda.
      # Inspired by a similar utility in RSpec:
      # https://github.com/rspec/rspec-expectations/blob/v3.9.2/lib/rspec/matchers/built_in/output.rb#L172-L197
      def self.capture_output
        original_stdout = $stdout.clone
        original_stderr = $stderr.clone
        captured_stream = Tempfile.new

        begin
          captured_stream.sync = true
          $stdout.reopen(captured_stream)
          $stderr.reopen(captured_stream)

          yield

          captured_stream.rewind
          captured_stream.read
        ensure
          $stdout.reopen(original_stdout)
          $stderr.reopen(original_stderr)
          captured_stream.close
          captured_stream.unlink
        end
      end

      # A subclass that forces rake to use our desired Rakefile, and configures Rake to act
      # a bit different.
      class Application < ::Rake::Application
        def initialize
          super
          @rakefiles = [RAKEFILE]
        end

        # Rake defines this to catch exceptions and call `exit(false)`, but we do not want
        # that behavior. We want to let lambda handle exceptions like normal.
        def standard_exception_handling
          yield
        end
      end
    end
  end
end
