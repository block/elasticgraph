# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "rubocop"
require "date"

module ElasticGraph
  class RequireStandardCommentHeader < ::RuboCop::Cop::Base
    extend ::RuboCop::Cop::AutoCorrector

    # At the top of every source file we want to include:
    # - The standard Block license header.
    # - The frozen string literal magic comment.
    #
    # The latter can have significant performance benefits, but standardrb (our linter) doesn't enforce it or
    # allow you to enforce it with the standard Rubucop Cop--so we are including it here.
    #
    # For further discussion, see:
    # https://github.com/standardrb/standard/pull/181

    def standard_comment_header
      <<~EOS
        # Copyright 2024 - #{Date.today.year} Block, Inc.
        #
        # Use of this source code is governed by an MIT-style
        # license that can be found in the LICENSE file or at
        # https://opensource.org/licenses/MIT.
        #
        # frozen_string_literal: true

      EOS
    end

    def on_new_investigation
      # Don't mess with files that start with a shebang line -- that must go first and can't be changed.
      return if processed_source.lines.first.start_with?("#!")

      header_lines = standard_comment_header.lines.map(&:chomp)
      last_leading_comment_line_number = find_last_leading_comment_line_number
      leading_comment_lines = processed_source.lines[0...last_leading_comment_line_number - 1]
      possible_header_lines = leading_comment_lines.first(header_lines.size)

      unless possible_header_lines == header_lines
        if possible_header_lines.join("\n").include?("Block, Inc.") && possible_header_lines.join("\n").include?("frozen_string_literal: true")
          range = processed_source.buffer.line_range(header_lines.size - 1)
          add_offense(range, message: "Standard header is out of date.") do |corrector|
            first_line_to_replace = processed_source.buffer.line_range(1)
            last_line_to_replace = processed_source.buffer.line_range(header_lines.size - 1)
            range = first_line_to_replace.join(last_line_to_replace)

            replacement =
              if processed_source.buffer.line_range(header_lines.size).source == ""
                standard_comment_header.strip
              else
                standard_comment_header.strip + "\n"
              end

            corrector.replace(range, replacement)
          end
        else
          range = processed_source.buffer.line_range(1)
          add_offense(range, message: "Missing standard comment header at top of file.") do |corrector|
            corrector.insert_before(range, standard_comment_header)
          end
        end
      end
    end

    def find_last_leading_comment_line_number
      processed_source.tokens.find { |token| !token.comment? }&.line || processed_source.lines.size
    end
  end
end
