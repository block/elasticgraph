# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "open3"

class ShSnippetValidator < SnippetValidator
  def validate(snippet)
    _, error, status = Open3.capture3("sh", "-n", stdin_data: snippet.content)

    status.success? ? ValidationResult.passed : ValidationResult.failed(error)
  rescue => e
    ValidationResult.failed("Shell syntax validation error: #{e.message}")
  end
end
