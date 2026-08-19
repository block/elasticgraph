# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Displays protobuf snippets without validating them. Most protobuf snippets in our READMEs are
# excerpts of a generated `schema.proto` (a few fields of one message, say) rather than complete
# proto files, so `protoc` cannot compile them on their own.
class ProtobufSnippetValidator < SnippetValidator
  def validate(snippet)
    puts "    📝 Protobuf content (unvalidated):"
    snippet.content.lines.each_with_index do |line, idx|
      puts "      #{idx + 1}: #{line}"
    end

    ValidationResult.unvalidated("Protobuf snippet displayed (no validation performed)")
  end
end
