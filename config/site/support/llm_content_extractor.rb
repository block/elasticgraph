# frozen_string_literal: true

require "nokogiri"
require_relative "content_extractor"

module ElasticGraph
  class LLMContentExtractor < ContentExtractor
    def initialize(jekyll_site_dir:, docs_dir:, output_file:)
      super(jekyll_site_dir: jekyll_site_dir, docs_dir: docs_dir)
      @output_file = output_file
    end

    def extract_and_write_content
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
        content << "### #{doc['title']}\n"
        content << doc['content']
        content << "\nURL: #{doc['url']}\n\n"
      end

      # Process markdown pages
      content << "## Site Documentation\n"
      markdown_content = process_markdown_pages
      markdown_content.each do |page|
        content << "### #{page['title']}\n"
        content << page['content']
        content << "\nURL: #{page['url']}\n\n"
      end

      # Write the final content
      FileUtils.mkdir_p(File.dirname(@output_file))
      File.write(@output_file, content.join("\n"))
      puts "Generated LLM documentation at #{@output_file}"
    end
  end
end