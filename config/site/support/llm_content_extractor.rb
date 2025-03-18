# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "content_extractor"

module ElasticGraph
  class LLMContentExtractor < ContentExtractor
    def initialize(jekyll_site_dir:, docs_dir:)
      super(jekyll_site_dir: jekyll_site_dir, docs_dir: docs_dir)
    end

    def extract_llm_content
      content = []
      content << "# ElasticGraph API Documentation\n"

      # Get the latest docs version and content
      latest_docs_version = Dir.entries(@docs_dir).grep(/^v/)
        .max_by { |v| Gem::Version.new(v.delete_prefix("v")) }

      puts "Processing API docs from latest version: #{latest_docs_version}"

      # Process API documentation
      content << "## API Documentation\n"
      api_docs_content = process_docs_directory(@docs_dir / latest_docs_version, latest_docs_version)
      api_docs_content.each do |doc|
        content << "### #{doc["title"]}\n"
        content << doc["content"]
        content << "\nURL: #{doc["url"]}\n\n"
      end

      # Process markdown pages
      content << "## Site Documentation\n"
      markdown_content = process_markdown_pages
      markdown_content.each do |page|
        content << "### #{page["title"]}\n"
        content << page["content"]
        content << "\nURL: #{page["url"]}\n\n"
      end

      full_content = content.join("\n")

      {
        "content" => full_content,
        "size" => full_content.bytesize,
        "version" => latest_docs_version,
        "generated_at" => Time.now.utc.iso8601
      }
    end
  end
end
