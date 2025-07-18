# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Data class to represent a code snippet from a README file
Snippet = Data.define(:content, :type, :source_file) do
  def self.extract_from(source_file)
    content = File.read(source_file)

    snippets = []
    in_code_block = false
    current_snippet = []
    current_type = nil

    content.lines.each do |line|
      stripped_line = line.strip

      if (match = stripped_line.match(/^```\s*(\w+)?\s*$/))
        if in_code_block
          # End of code block
          in_code_block = false
          snippet_content = current_snippet.join

          unless snippet_content.strip.empty?
            snippets << Snippet.new(content: snippet_content, type: current_type, source_file: source_file)
          end
        else
          # Start of code block
          in_code_block = true
          current_snippet = []
          current_type = match[1]&.downcase || "text"
        end
      elsif in_code_block
        current_snippet << line
      end
    end

    snippets
  end
end
