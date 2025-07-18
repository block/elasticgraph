# Copyright 2024 - 2025 Block, Inc.
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
