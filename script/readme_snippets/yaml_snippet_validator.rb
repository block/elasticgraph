# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "yaml"

class YamlSnippetValidator < SnippetValidator
  def validate(snippet)
    # Parse the YAML to check for syntax errors
    YAML.safe_load(snippet.content)

    # If we get here, the YAML parsed successfully
    ValidationResult.passed
  rescue Psych::SyntaxError => e
    ValidationResult.failed("YAML syntax error: #{e.message}")
  rescue => e
    ValidationResult.failed("YAML parsing error: #{e.message}")
  end
end
