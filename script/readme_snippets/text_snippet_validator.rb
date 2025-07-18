# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

class TextSnippetValidator < SnippetValidator
  def validate(snippet)
    puts "    📝 Text content (unvalidated):"
    snippet.content.lines.each_with_index do |line, idx|
      puts "      #{idx + 1}: #{line}"
    end

    ValidationResult.unvalidated("Text snippet displayed (no validation performed)")
  end
end
