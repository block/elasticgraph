# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "nokogiri"

module ElasticGraph
  class MermaidProcessor
    def initialize(docs_path)
      @docs_path = docs_path
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

      # Find mermaid code blocks - look for <pre><code> blocks that contain mermaid syntax
      mermaid_blocks = find_mermaid_blocks(doc)

      return false if mermaid_blocks.empty?

      # Add mermaid.js script to head if not already present
      add_mermaid_script(doc) unless has_mermaid_script?(doc)

      # Convert code blocks to mermaid divs
      convert_code_blocks_to_mermaid(mermaid_blocks)

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

      # Add mermaid.js CDN script
      script = doc.create_element("script", "", {
        "src" => "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"
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
  end
end
