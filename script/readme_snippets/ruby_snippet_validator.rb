# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "snippet_validator"
require "fileutils"
require "shellwords"

class RubySnippetValidator < SnippetValidator
  # Constants for Ruby snippet validation
  RACK_TIMEOUT_SECONDS = 10

  # Rack config detection patterns
  RACK_SUCCESS_INDICATORS = [
    "Listening on",
    "Use Ctrl-C to stop",
    "WEBrick::HTTPServer#start"
  ].freeze

  RACK_FAILURE_INDICATORS = %w[Error LoadError NameError].freeze

  def validate(snippet)
    execute_in_temp_project do
      file_path = extract_file_path_from_snippet(snippet.content)
      temp_file_path = create_ruby_file(snippet.content, file_path)

      begin
        success, output = if rack_config?(snippet.content)
          execute_rack_config(temp_file_path)
        elsif schema_definition?(snippet.content, temp_file_path)
          dump_artifacts
        else
          execute_ruby_file(temp_file_path)
        end

        show_debug_output(output) if !success || !output.strip.empty?
        success ? ValidationResult.passed(output) : ValidationResult.failed(output)
      ensure
        cleanup_temp_file(temp_file_path, file_path)
      end
    end
  rescue => e
    ValidationResult.failed("Exception during Ruby snippet validation: #{e.message}")
  end

  private

  def extract_file_path_from_snippet(snippet)
    # Check if the first line is a comment containing a .rb file path
    first_line = snippet.lines.first&.strip
    return nil unless first_line&.start_with?("#")

    # Extract everything after the # and check if it contains .rb
    comment_content = first_line[1..].strip
    return nil if comment_content.empty?

    # Look for a .rb file path in the comment
    if comment_content.match?(/\S+\.rb\b/)
      # Extract the file path (first word that ends with .rb)
      file_path = comment_content.split.find { |word| word.end_with?(".rb") }
      # Remove any trailing punctuation
      file_path&.gsub(/[.,;:!?]+$/, "")
    end
  end

  def create_ruby_file(snippet, file_path)
    if file_path
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, snippet)
      file_path
    else
      FileUtils.mkdir_p("tmp")
      is_rack_config = snippet.lines.last&.strip&.start_with?("run ")
      file_extension = is_rack_config ? ".ru" : ".rb"
      temp_file_path = File.join("tmp", "snippet_#{Time.now.to_f.to_s.tr(".", "_")}#{file_extension}")
      File.write(temp_file_path, snippet)
      temp_file_path
    end
  end

  def rack_config?(snippet)
    snippet.lines.last&.strip&.start_with?("run ")
  end

  def schema_definition?(snippet, file_path)
    file_path.include?("config/schema") && snippet.include?("ElasticGraph.define")
  end

  def dump_artifacts
    output = `bundle exec rake schema_artifacts:dump 2>&1`
    [$?.success?, output]
  end

  def execute_ruby_file(temp_file_path)
    output = `bundle exec ruby #{Shellwords.escape(temp_file_path)} 2>&1`
    [$?.success?, output]
  end

  def cleanup_temp_file(temp_file_path, file_path)
    # Only clean up temporary files (not files created at specific paths)
    File.delete(temp_file_path) if !file_path && File.exist?(temp_file_path)
  end

  def execute_rack_config(config_file_path)
    rackup_output = "tmp/rackup_output.log"

    success, output = execute_process_with_timeout(RACK_TIMEOUT_SECONDS) do
      spawn("bundle", "exec", "rackup", config_file_path, "--port", "0", out: rackup_output, err: rackup_output)
    end

    # For rack configs, we need to check the output file for success indicators
    if File.exist?(rackup_output)
      output = File.read(rackup_output)

      # Check for successful boot indicators
      if RACK_SUCCESS_INDICATORS.any? { |indicator| output.include?(indicator) } ||
          output.match?(/port=\d+/)
        success = true
      end

      # Check for obvious failures
      if RACK_FAILURE_INDICATORS.any? { |indicator| output.include?(indicator) }
        success = false
      end

      File.delete(rackup_output)
    end

    [success, output]
  rescue => e
    File.delete(rackup_output) if File.exist?(rackup_output)
    [false, "Exception during Rack config validation: #{e.message}"]
  end
end
