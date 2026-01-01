# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "nokogiri"

module ElasticGraph
  class ValidateNoEmptyCodeSnippets
    def initialize(jekyll_site_dir)
      @jekyll_site_dir = jekyll_site_dir
    end

    def validate!
      buttons_by_file =
        Dir.glob(File.join(@jekyll_site_dir, "**", "*.html")).to_h do |file|
          content = File.read(file)
          doc = Nokogiri::HTML(content)
          [file, doc.css("button.copy-to-clipboard")]
        end

      if buttons_by_file.values.flatten.empty?
        raise "No `button.copy-to-clipboard` elements found."
      end

      files_with_empty_snippets = buttons_by_file.filter_map do |file, buttons|
        file unless buttons.all? do |button|
          copied_code = button["onclick"][/\AcopyToClipboard\(this, (.+)\)\z/, 1]
          /\A".+"\z/.match?(copied_code)
        end
      end

      unless files_with_empty_snippets.empty?
        abort <<~EOS
          #{files_with_empty_snippets.size} HTML files have empty code snippets. Perhaps their `data=path.to.snippet` arguments in their markdown `copyable_code_snippet` includes are invalid?

          #{files_with_empty_snippets.map.with_index(1) { |f, i| "  #{i}. #{f}" }.join("\n")}
        EOS
      end
    end
  end
end
