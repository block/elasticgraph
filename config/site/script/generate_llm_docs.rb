#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "pathname"
require "fileutils"

def format_section_title(file_path)
  # Extract just the filename without extension and convert to title
  base_name = File.basename(file_path, ".md")
  title = base_name.tr("-", " ").split.map(&:capitalize).join(" ")
  "## #{title}"
end

def process_markdown_file(file_path)
  content = File.read(file_path)

  # Strip front matter
  if content =~ /\A(---\s*\n.*?\n?)^((---|\.\.\.)\s*$\n?)/m
    content = content.sub($1 + $2, "")
  end

  # Replace Jekyll highlight blocks with markdown code fences
  content.gsub!(/{% highlight graphql %}/, "```graphql")
  content.gsub!(/{% endhighlight %}/, "```")

  # Replace Jekyll link tags with markdown links
  content.gsub!(/{% link ([^%]+) %}/) do |match|
    link_path = $1.strip
    # Convert the Jekyll link to a simple markdown link
    # Remove .md extension and convert path to URL format
    url_path = link_path.sub(/\.md$/, "").gsub(/^query-api\//, "")
    "[#{url_path}](##{url_path})"
  end

  # Remove Jekyll includes
  content.gsub!(/{% include [^%]+ %}/, "")

  # Remove Kramdown style attributes
  content.gsub!(/{:\s*\.[^}]+}/, "")  # Remove class attributes like {: .alert-warning}

  # Handle alert blocks - convert to standard markdown
  content.gsub!(/\*\*Warning\*\*{:\s*\.alert-title}/, "**Warning:**")
  content.gsub!(/\*\*Note\*\*{:\s*\.alert-title}/, "**Note:**")

  # Remove any empty lines created by our replacements
  content.gsub!(/\n{3,}/, "\n\n")

  content
end

def process_data_references(content, data_dir)
  Dir.glob(data_dir / "*.yaml").each do |data_file|
    puts "Processing data file: #{data_file}"
    data = YAML.load_file(data_file)
    basename = File.basename(data_file, ".yaml")
    data.each do |category, queries|
      queries.each do |name, query|
        placeholder = "{{ site.data.#{basename}.#{category}.#{name} }}"
        puts "Replacing #{placeholder}"
        content.gsub!(placeholder, query)
      end
    end
  end
  content
end

def generate_llm_docs(site_config_dir:, site_source_dir:)
  # Define output directory and file - now directly in src/_data
  output_dir = site_source_dir / "_data"
  output_file = output_dir / "llms-full.txt"
  FileUtils.mkdir_p(output_dir)

  # Start with a header
  content = []
  content << "# ElasticGraph Documentation"

  # Define the order of documentation files
  doc_files = [
    "query-api.md",
    "query-api/aggregations.md",
    "query-api/aggregations/counts.md",
    "query-api/aggregations/grouping.md",
    "query-api/aggregations/aggregated-values.md",
    "query-api/aggregations/sub-aggregations.md",
    "query-api/filtering.md",
    "query-api/filtering/available-predicates.md",
    "query-api/filtering/comparison.md",
    "query-api/filtering/equality.md",
    "query-api/filtering/full-text-search.md",
    "query-api/filtering/geographic.md",
    "query-api/filtering/list.md",
    "query-api/filtering/negation.md",
    "query-api/pagination.md",
    "query-api/sorting.md"
  ]

  # Process each file in order
  doc_files.each do |file_path|
    full_path = site_source_dir / file_path
    if File.exist?(full_path)
      puts "Processing #{file_path}"
      # Add section title
      content << format_section_title(file_path) << "\n"
      section_content = process_markdown_file(full_path)
      section_content = process_data_references(section_content, site_source_dir / "_data")
      content << section_content << "\n"
    else
      puts "Warning: #{file_path} not found"
    end
  end

  # Write the final content
  puts "Writing output to: #{output_file}"
  File.write(output_file, content.join("\n"))
  puts "Generated LLM documentation at #{output_file}"

  # Also create a Jekyll-compatible source file that will serve the content
  jekyll_source = <<~YAML
    ---
    layout: none
    permalink: /llms-full.txt
    ---
    {% include_relative _data/llms-full.txt %}
  YAML

  File.write(site_source_dir / "llms-full.txt", jekyll_source)
  puts "Created Jekyll source file at #{site_source_dir / "llms-full.txt"}"
end

# Allow running directly from command line
if __FILE__ == $PROGRAM_NAME
  site_config_dir = Pathname.new(ARGV[0] || Dir.pwd)
  site_source_dir = site_config_dir / "src"

  unless File.directory?(site_source_dir)
    puts "Error: src directory not found in #{site_config_dir}"
    exit 1
  end

  generate_llm_docs(
    site_config_dir: site_config_dir,
    site_source_dir: site_source_dir
  )
end
