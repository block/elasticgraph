# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "json"

class JsonSnippetValidator < SnippetValidator
  def validate(snippet)
    JSON.parse(snippet.content)

    ValidationResult.passed
  rescue JSON::ParserError => e
    ValidationResult.failed("JSON syntax error: #{e.message}")
  end
end
