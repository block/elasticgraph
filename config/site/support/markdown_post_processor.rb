# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "nokogiri"
require "net/http"
require "uri"
require "fileutils"

module ElasticGraph
  # Responsible for processing HTML files generated from markdown files by YARD. Our READMEs are primarily written to
  # look good on GitHub, and to ensure they look good and work correctly in our YARD docs, we have to do a few things:
  #
  # * Inject mermaid.js so that diagrams render correctly.
  # * Inject highlight.js so that non-Ruby code snippets are highlighted. (YARD only natively supports Ruby highlighting).
  # * Fix relative links to GitHub files to instead be local links to the YARD files.
  class MarkdownPostProcessor
    HIGHLIGHT_JS_VERSION = "11.9.0"
    HIGHLIGHT_JS_CSS_URL = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/#{HIGHLIGHT_JS_VERSION}/styles/github.min.css"
    HIGHLIGHT_JS_JS_URL = "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/#{HIGHLIGHT_JS_VERSION}/highlight.min.js"
    MERMAID_JS_URL = "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"

    def initialize(docs_path, staged_markdown_mappings)
      @docs_path = docs_path
      @staged_markdown_mappings = staged_markdown_mappings
      @assets_dir = File.join(@docs_path, "assets")
    end

    def process!
      html_files = Dir.glob(File.join(@docs_path, "**", "*.html"))
      processed_count = 0

      html_files.each do |file_path|
        if process_file(file_path)
          processed_count += 1
        end
      end

      puts "Mermaid.js integration complete! Processed #{processed_count} files."
    end

    private

    def process_file(file_path)
      doc = File.open(file_path) { |f| Nokogiri::HTML(f) }
      modified = false

      # Find mermaid code blocks - look for <pre><code> blocks that contain mermaid syntax
      mermaid_blocks = find_mermaid_blocks(doc)

      if !mermaid_blocks.empty?
        # Add mermaid.js script to head if not already present
        add_mermaid_script(doc) unless has_mermaid_script?(doc)

        # Convert code blocks to mermaid divs
        convert_code_blocks_to_mermaid(mermaid_blocks)
        modified = true
      end

      # Rewrite README links to YARD file links
      if rewrite_readme_links(doc)
        modified = true
      end

      # Add highlight.js for syntax highlighting
      if add_highlight_js(doc)
        modified = true
      end

      return false unless modified

      # Write back to file
      File.write(file_path, doc.to_html)

      relative_path = file_path.sub(@docs_path.to_s + "/", "")
      puts "  ✓ Added Mermaid.js support to #{relative_path}"

      true
    end

    def find_mermaid_blocks(doc)
      doc.css("pre code").select do |code|
        content = code.text.strip
        # Check if content starts with common mermaid diagram types
        mermaid_keywords = %w[
          graph flowchart sequenceDiagram classDiagram stateDiagram
          gantt pie journey gitGraph erDiagram mindmap timeline
          quadrantChart xyChart block-beta
        ]

        mermaid_keywords.any? { |keyword| content.start_with?(keyword) }
      end
    end

    def has_mermaid_script?(doc)
      doc.css('script[src*="mermaid"]').any?
    end

    def add_mermaid_script(doc)
      head = doc.at_css("head")
      return unless head

      # Ensure mermaid.js assets are downloaded and available locally
      ensure_mermaid_assets!

      # Add mermaid.js script (using local path)
      script = doc.create_element("script", "", {
        "src" => "assets/mermaid.min.js"
      })
      head.add_child(script)

      # Add CSS for GitHub-like diagram styling
      style = doc.create_element("style", <<~CSS.strip)
        .mermaid {
          max-width: 100%;
          margin: 20px 0;
          border: 1px solid #e1e4e8;
          border-radius: 6px;
          padding: 16px;
          background-color: #f6f8fa;
          text-align: center;
        }

        .mermaid svg {
          max-width: 100%;
          height: auto;
          display: block;
          margin: 0 auto;
        }
      CSS
      head.add_child(style)

      # Add simple initialization script
      init_script = doc.create_element("script", <<~JS.strip)
        document.addEventListener('DOMContentLoaded', function() {
          mermaid.initialize({
            startOnLoad: true,
            theme: 'default',
            securityLevel: 'loose',
            // Better visual configuration
            flowchart: {
              useMaxWidth: true,
              htmlLabels: true,
              curve: 'basis'
            },
            sequence: {
              useMaxWidth: true,
              wrap: true
            },
            gantt: {
              useMaxWidth: true
            },
            // Improved text handling
            maxTextSize: 90000,
            suppressErrorRendering: false,
            logLevel: 'error'
          });
        });
      JS
      head.add_child(init_script)
    end

    def convert_code_blocks_to_mermaid(mermaid_blocks)
      mermaid_blocks.each do |code_block|
        pre_parent = code_block.parent
        doc = code_block.document

        # Create new mermaid div with the code content
        mermaid_div = doc.create_element("div", code_block.text.strip, {
          "class" => "mermaid"
        })

        # Replace the <pre><code> block with the mermaid div
        pre_parent.replace(mermaid_div)
      end
    end

    def rewrite_readme_links(doc)
      return false if @staged_markdown_mappings.empty?

      modified = false

      # Find all links in the document
      doc.css("a[href]").each do |link|
        href = link["href"]

        # Check if this link matches any of our staged README mappings
        @staged_markdown_mappings.each do |original_path, yard_filename|
          if href == original_path
            # Convert to YARD file link format
            new_href = "file.#{yard_filename.delete_suffix(".md")}.html"
            link["href"] = new_href
            modified = true
            break
          end
        end
      end

      modified
    end

    def add_highlight_js(doc)
      # Check if the document has code blocks that could benefit from syntax highlighting
      has_code_blocks = doc.css("pre.code code").any? do |code_element|
        # Get the language from the code element's class
        language = extract_language_from_code_element(code_element)
        language && language != "mermaid"
      end

      return false unless has_code_blocks

      head = doc.at_css("head")
      return false unless head

      # Check if highlight.js is already included
      return false if head.css('script[src*="highlight"]').any?

      # Ensure assets are downloaded and available locally
      ensure_highlight_js_assets!

      # Add highlight.js CSS (using local path)
      css_link = doc.create_element("link", "", {
        "rel" => "stylesheet",
        "href" => "assets/highlight.min.css"
      })
      head.add_child(css_link)

      # Add highlight.js script (using local path)
      script = doc.create_element("script", "", {
        "src" => "assets/highlight.min.js"
      })
      head.add_child(script)

      # Add initialization script
      init_script = doc.create_element("script", <<~JS.strip)
        document.addEventListener('DOMContentLoaded', function() {
          // Configure highlight.js to work with YARD's code block structure
          document.querySelectorAll('pre.code code').forEach(function(block) {
            // Get the language from the code element's class
            const classes = block.className.split(' ');
            const language = classes.find(cls => cls.match(/^[a-z]+$/) && cls !== 'code');

            if (language && language !== 'mermaid') {
              // Set the language class for highlight.js
              block.className = 'language-' + language;
              hljs.highlightElement(block);
            }
          });
        });
      JS
      head.add_child(init_script)

      true
    end

    def ensure_highlight_js_assets!
      FileUtils.mkdir_p(@assets_dir)

      css_path = File.join(@assets_dir, "highlight.min.css")
      js_path = File.join(@assets_dir, "highlight.min.js")

      # Download CSS if not present
      unless File.exist?(css_path)
        puts "  → Downloading highlight.js CSS..."
        download_file(HIGHLIGHT_JS_CSS_URL, css_path)
      end

      # Download JS if not present
      unless File.exist?(js_path)
        puts "  → Downloading highlight.js JavaScript..."
        download_file(HIGHLIGHT_JS_JS_URL, js_path)
      end
    end

    def ensure_mermaid_assets!
      FileUtils.mkdir_p(@assets_dir)

      js_path = File.join(@assets_dir, "mermaid.min.js")

      # Download JS if not present
      unless File.exist?(js_path)
        puts "  → Downloading mermaid.js JavaScript..."
        download_file(MERMAID_JS_URL, js_path)
      end
    end

    def download_file(url, destination)
      uri = URI(url)
      response = Net::HTTP.get_response(uri)

      if response.is_a?(Net::HTTPSuccess)
        File.write(destination, response.body)
      else
        raise "Failed to download #{url}: #{response.code} #{response.message}"
      end
    end

    def extract_language_from_code_element(code_element)
      # Extract language from class attribute (e.g., "ruby" from class="ruby")
      class_attr = code_element["class"]
      return nil unless class_attr

      # Handle multiple classes - look for the language class
      classes = class_attr.split(/\s+/)
      # Return the first class that looks like a language identifier
      classes.find { |cls| cls.match?(/^[a-z]+$/) && cls != "code" }
    end
  end
end
