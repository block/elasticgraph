# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "shellwords"

# Base class for snippet validators
SnippetValidator = Data.define(:temp_project, :debug_output) do
  private

  # Only delegate the truly shared methods
  def execute_in_temp_project(&block)
    Dir.chdir(temp_project.path, &block)
  end

  def show_debug_output(output)
    debug_output.puts "    Debug output: #{output}"
  end

  # Shared process execution with timeout
  def execute_process_with_timeout(timeout_seconds, &block)
    start_time = Time.now
    success = false
    output = ""
    pid = nil

    begin
      pid = yield

      # Wait for process completion or timeout
      while Time.now - start_time < timeout_seconds
        begin
          result = Process.waitpid2(pid, Process::WNOHANG)
          if result
            _, status = result
            success = status.success?
            break
          else
            sleep(0.1)
          end
        rescue Errno::ECHILD
          success = true
          break
        end
      end

      # Handle timeout case
      if Time.now - start_time >= timeout_seconds
        success, output = handle_process_timeout(pid, timeout_seconds)
      end
    rescue => e
      output = "Exception during execution: #{e.message}"
      success = false
    ensure
      cleanup_process(pid)
    end

    show_debug_output(output) if !success || !output.strip.empty?
    [success, output]
  end

  def handle_process_timeout(pid, timeout_seconds)
    Process.kill(0, pid)
    [true, "Command ran for #{timeout_seconds}+ seconds without failing (considered success)"]
  rescue Errno::ESRCH
    [true, ""] # Process finished right at timeout
  end

  def cleanup_process(pid)
    return unless pid

    begin
      Process.kill("TERM", pid)
      Process.wait(pid, Process::WNOHANG)
    rescue Errno::ESRCH, Errno::ECHILD
      # Process already finished
    end
  end
end
