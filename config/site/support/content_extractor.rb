# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "nokogiri"

module ElasticGraph
  class ContentExtractor
    def initialize(jekyll_site_dir:, docs_dir:)
      @jekyll_site_dir = jekyll_site_dir
      @docs_dir = docs_dir
    end

    def extract_content
      # Get the latest docs version
      latest_docs_version = Dir.entries(@docs_dir).grep(/^v/)
        .max_by { |v| Gem::Version.new(v.delete_prefix("v")) }

      puts "Indexing API docs from latest version: #{latest_docs_version}"

      # Extract docs content - without code blocks for search
      api_docs_content = process_docs_directory(@docs_dir / latest_docs_version, latest_docs_version)
      markdown_content = process_markdown_pages

      # Build the searchable content
      searchable_content = api_docs_content + markdown_content

      # Get markdown content again - with code blocks for LLM
      markdown_content_with_code = process_markdown_pages(include_code_blocks: true)

      # Build the LLM content
      llm_content = []
      llm_content << "# ElasticGraph API Documentation\n"
      llm_content << "## API Documentation\n"

      api_docs_content.each do |doc|
        llm_content << "### #{doc.fetch("title")}\n"
        llm_content << "#{doc.fetch("content")}\n\n"
      end

      llm_content << "## Site Documentation\n"
      markdown_content_with_code.each do |page|
        llm_content << "### #{page.fetch("title")}\n"
        llm_content << "#{page.fetch("content")}\n\n"
      end

      full_llm_content = llm_content.join("\n")

      {
        "searchable_content" => searchable_content,
        "llm_content" => {
          "content" => full_llm_content,
          "size" => full_llm_content.bytesize,
          "version" => latest_docs_version,
          "generated_at" => Time.now.utc.iso8601
        }
      }
    end

    private

    # Common YARD-generated phrases that we want to exclude from search indexing
    YARD_PHRASES_TO_REMOVE = [
      /Generated on.*?by yard.*?ruby.*?\)\./,
      "Overview",
      /This (?:class|method|module|constant) is part of a private API\. You should avoid using this (?:class|method|module|constant) if possible, as it may be removed or be changed in the future\./,
      /This (?:class|method|module|constant) is private\./,
      /This is a private (?:class|method|module|constant)\./,
      "Returns:",
      "Returns — ",
      /(see .+? for more details)/,  # Regex to match cross-references
      "Implementation from",
      "Implementation detail:",
      "Source:",
      "File:",
      "Defined in:",
      /(also: #[a-zA-Z_]+)/,  # Regex to match "also: #method_name" references
      "View source",
      "Toggle source",
      "Toggle Docs",
      "Permalink"
    ].freeze

    def extract_file_content(file_path)
      content = File.read(file_path)
      doc = Nokogiri::HTML(content)

      # Remove script, style, and line number elements
      doc.css("script, style").remove

      # Get the main content without line numbers and source code
      doc.css(".line-numbers, .line, .source_code, .file").remove
      main_content = doc.css("#main").text

      # Get method details - just the signatures and docstrings
      method_details = doc.css(".method_details .method_signature, .method_details .docstring").text

      # Combine and clean up the text
      content = [main_content, method_details].join(" ")
      content.gsub!(/\s+/, " ") # normalize whitespace

      # Remove common YARD-generated phrases
      YARD_PHRASES_TO_REMOVE.each do |phrase|
        content.gsub!(phrase, "")
      end

      content.gsub!(/\s+/, " ") # normalize whitespace again after removals
      content.strip!

      # Get the title
      title = doc.css("title").text.strip
      title = title.split(" - ").first if title.include?(" - ")
      title = title.sub(/\s*— Documentation by YARD.*$/, "") # Remove YARD suffix

      [title, content]
    end

    def process_docs_directory(dir, version)
      Dir.glob(File.join(dir, "**", "*.html")).filter_map do |file|
        next if file.include?("/css/") || file.include?("/js/")
        next if %w[frames.html file_list.html class_list.html method_list.html].include?(File.basename(file))

        title, content = extract_file_content(file)
        next if content.empty?

        # Generate URL with /docs/version/ prefix
        relative_path = file.sub(dir.to_s, "")
        url = "/docs/#{version}#{relative_path}"

        {
          "title" => "API Documentation - #{title}",
          "url" => url,
          "content" => content
        }
      end
    end

    # Process markdown pages
    def process_markdown_pages(include_code_blocks: false)
      # Now process the rendered HTML files
      Dir.glob(File.join(@jekyll_site_dir, "**", "*.html")).filter_map do |file|
        # Skip files we don't want to index
        next if file.include?("/css/") || file.include?("/js/")
        next if %w[frames.html file_list.html class_list.html method_list.html].include?(File.basename(file))
        next if file.include?("/docs/") # Skip API docs, we handle those separately

        # Get the rendered content
        content = File.read(file)
        doc = Nokogiri::HTML(content)

        # Remove navigation elements, scripts, etc
        doc.css("nav, script, style, footer").remove

        # Get code blocks if needed
        code_blocks = include_code_blocks ? extract_code_blocks(doc) : []

        # Get the main content
        main = doc.css("main")

        # Remove code blocks from main content to avoid duplication
        main.css("figure.highlight").remove if include_code_blocks

        # Get text content
        text_content = main.text.strip
        next if text_content.empty?

        # Clean up the content
        text_content = text_content.gsub(/\s+/, " ").strip

        # Add code blocks if requested
        content = if include_code_blocks && !code_blocks.empty?
          text_content + "\n\n" + code_blocks.join("\n")
        else
          text_content
        end

        # Get the title
        title = doc.css("h1, h2").first&.text&.strip || doc.title

        # Get the relative URL
        relative_path = file.sub(@jekyll_site_dir.to_s, "").delete_suffix("index.html")

        {
          "title" => title,
          "url" => relative_path,
          "content" => content
        }
      end
    end

    def extract_code_blocks(doc)
      doc.css("figure.highlight").filter_map do |figure|
        if (code = figure.css("code").first)
          lang = code["data-lang"]
          text = code.text.strip

          "```#{lang}\n#{text}\n```\n"
        end
      end
    end
  end
end
