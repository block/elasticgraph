# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "snippet_validator"
require "tempfile"

class BashSnippetValidator < SnippetValidator
  BASH_TIMEOUT_SECONDS = 5

  def validate(snippet)
    # TODO(#971): remove this work around once ElasticGraph 1.0.3 is released.
    if RUBY_VERSION.start_with?("4.0") && snippet.content.include?("gem exec elasticgraph new")
      return ValidationResult.skipped("Can't run `gem exec elasticgraph new` on Ruby 4.0 until we've released a version of the `elasticgraph` gem compatible with 4.0.")
    end

    execute_in_temp_project do
      Tempfile.create do |output_file|
        success, _ = execute_process_with_timeout(BASH_TIMEOUT_SECONDS) do
          spawn("bash", "-c", snippet.content, [:out, :err] => output_file)
        end

        # Read the output from the file
        output = File.exist?(output_file) ? File.read(output_file) : ""

        success ? ValidationResult.passed(output) : ValidationResult.failed(output)
      end
    end
  rescue => e
    ValidationResult.failed("Exception during bash snippet validation: #{e.message}")
  end
end
