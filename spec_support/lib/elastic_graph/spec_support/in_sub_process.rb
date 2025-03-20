# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  # We use `aggregate_failures: false` here because aggregating failures does not work well with
  # child processes. Any failures get aggregated into state in the child process that gets lost
  # when the process exits.
  ::RSpec.shared_context "in_sub_process", aggregate_failures: false do
    # Runs the provided block in a subprocess. Any failures in the sub process get
    # caught and re-raised in the parent process. Also, this returns the return value
    # of the child process (using `Marshal` to send it across a pipe).
    def in_sub_process(&block)
      SubProcess.new.run(&block)
    end
  end

  class SubProcess < ::Data.define(:reader, :writer)
    def initialize
      reader, writer = ::IO.pipe
      super(reader: reader, writer: writer)
    end

    def run(&block)
      pid = ::Process.fork { in_child_process(&block) }
      in_parent_process(pid)
    end

    private

    def in_parent_process(pid)
      writer.close # We don't write from the parent process

      ::Process.waitpid(pid)

      result, exception = ::Marshal.load(reader.read)
      # :nocov: -- which branch is taken depends on if a test is failing.
      raise exception if exception
      # :nocov:
      result
    ensure
      reader.close
    end

    def in_child_process
      reader.close # We don't read from the child process

      handle_exceptions do
        result = yield
        handle_exceptions(" (exception received while marshaling the result)") do
          writer.write(::Marshal.dump([result, nil]))
        end
      end
    ensure
      writer.close
    end

    def handle_exceptions(suffix = "")
      yield
    rescue ::Exception => ex # standard:disable Lint/RescueException
      # :nocov: -- we only get here when there's a problem.
      # Not all exceptions can be marshaled (e.g. if they have state that references unmarshable objects such as a proc).
      # Here we just use a `StandardError` with the same message and backtrace to ensure it can be marshaled.
      replacement_exception = ::StandardError.new("#{ex.class}: #{ex.message}#{suffix}")
      replacement_exception.set_backtrace(ex.backtrace)
      writer.write(::Marshal.dump([nil, replacement_exception]))
      # :nocov:
    end
  end
end
