# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "pathname"
require "stringio"
require_relative "validation_result"
require_relative "temp_elastic_graph_project"
require_relative "snippet"
require_relative "ruby_snippet_validator"
require_relative "diff_snippet_validator"
require_relative "bash_snippet_validator"
require_relative "yaml_snippet_validator"
require_relative "text_snippet_validator"
require_relative "mermaid_snippet_validator"
require_relative "fallback_snippet_validator"

class ReadmeSnippetValidator
  def initialize(repo_root = File.expand_path("../..", __dir__))
    @repo_root = repo_root
    @failures = []
    @total_snippets = 0
    @options = {
      verbose: false,
      specific_file: nil
    }
  end

  def validate_all(options = {})
    @options.merge!(options)

    puts "🔍 Scanning for README.md files with code snippets..."

    readme_files = find_readme_files

    # Extract all snippets upfront
    @snippets_by_file = extract_snippets_from_files(readme_files)

    # Count snippets for summary
    snippet_counts = count_snippets_by_type
    total_snippets = snippet_counts.values.sum

    # Create dynamic snippet count message
    count_parts = snippet_counts.sort.map { |type, count| "#{count} #{type}" }

    puts "📄 Found #{readme_files.size} README.md files with #{total_snippets} snippets (#{count_parts.join(", ")})"

    with_temp_project do |temp_project|
      @snippets_by_file.each do |readme_path, snippets|
        temp_project.sandbox do
          validate_readme_snippets(readme_path, snippets)
        end
      end

      report_results
      exit(1) if @failures.any?
    end
  end

  private

  def find_readme_files
    if @options[:specific_file]
      [::File.expand_path(@options[:specific_file], @repo_root)]
    else
      find_git_tracked_readme_files
    end
  end

  def find_git_tracked_readme_files
    Dir.chdir(@repo_root) do
      output = `git ls-files '**/README.md' 'README.md' 2>/dev/null`

      if $?.success?
        output.lines.map(&:strip).reject(&:empty?).map do |relative_path|
          File.expand_path(relative_path, @repo_root)
        end
      else
        puts "❌ Error: Failed to run 'git ls-files'. This script requires git."
        exit(1)
      end
    end
  end

  def extract_snippets_from_files(readme_files)
    readme_files.to_h do |readme_path|
      [readme_path, Snippet.extract_from(readme_path)]
    end
  end

  def count_snippets_by_type
    @snippets_by_file.values.flat_map do |snippets|
      snippets.map(&:type)
    end.tally
  end

  def validate_readme_snippets(readme_path, snippets)
    relative_path = relative_path_for(readme_path)

    return if snippets.empty?

    report_validation_start_for_file(snippets, relative_path)

    # Validate all snippets
    snippets.each_with_index do |snippet, index|
      validate_snippet_object(snippet, index + 1)
    end
  end

  def report_untested_snippets_for_file(untested_snippets, relative_path)
    untested_types = untested_snippets.map(&:type).uniq.sort
    puts "\n⚠️  Found #{untested_snippets.size} untested snippet(s) in #{relative_path} (types: #{untested_types.join(", ")})"

    untested_snippets.each_with_index do |snippet, index|
      @untested_snippets << {
        file: relative_path,
        snippet_number: index + 1,
        type: snippet.type,
        snippet: snippet.content
      }
    end
  end

  def report_validation_start_for_file(snippets, relative_path)
    # Group snippets by type for reporting
    snippets_by_type = snippets.group_by(&:type)
    counts = snippets_by_type.sort.map { |type, snippets| "#{snippets.size} #{type}" }
    total = snippets.size
    puts "\n📝 Validating #{total} snippet(s) from #{relative_path} (#{counts.join(", ")})"
  end

  def validate_snippet_object(snippet, snippet_number)
    @total_snippets += 1

    show_snippet_details_for_object(snippet, snippet_number) if @options[:verbose]

    validator = @snippet_validators[snippet.type] || @fallback_validator
    result = validator.validate(snippet)

    puts "  #{result.emoji} Snippet ##{snippet_number} (#{snippet.type}) - #{result.status.upcase}"

    unless result.success?
      record_failure_for_object(snippet, snippet_number, result.output)
      show_immediate_failure_details(snippet, snippet_number, result.output)
    end
  end

  def show_snippet_details_for_object(snippet, snippet_number)
    puts "  🔍 Validating #{snippet.type} snippet ##{snippet_number}:"
    snippet.content.lines.each_with_index do |line, idx|
      puts "    #{idx + 1}: #{line}"
    end
  end

  def show_immediate_failure_details(snippet, snippet_number, output)
    relative_path = relative_path_for(snippet.source_file)

    puts "\n    💥 FAILURE DETAILS:"
    puts "    📄 File: #{relative_path}"
    puts "    🔢 Snippet: #{snippet.type} ##{snippet_number}"
    puts "    📝 Code:"
    snippet.content.lines.each_with_index do |line, idx|
      puts "      #{idx + 1}: #{line}"
    end

    if output && !output.strip.empty?
      puts "    ❌ Error Output:"
      output.lines.each do |error_line|
        puts "      #{error_line}"
      end
    end
    puts # Add blank line for readability
  end

  def record_failure_for_object(snippet, snippet_number, output)
    relative_path = relative_path_for(snippet.source_file)
    @failures << {
      file: relative_path,
      snippet_number: snippet_number,
      snippet: snippet.content,
      error_output: output,
      type: snippet.type.to_sym
    }
  end

  def relative_path_for(readme_path)
    Pathname.new(readme_path).relative_path_from(Pathname.new(@repo_root))
  end

  def with_temp_project
    TempElasticGraphProject.new(@repo_root) do |project|
      verbose_output = @options[:verbose] ? $stdout : ::StringIO.new

      # Create validators for all snippet types
      @snippet_validators = {
        "ruby" => RubySnippetValidator.new(project, verbose_output),
        "diff" => DiffSnippetValidator.new(project, verbose_output),
        "bash" => BashSnippetValidator.new(project, verbose_output),
        "yaml" => YamlSnippetValidator.new(project, verbose_output),
        "text" => TextSnippetValidator.new(project, verbose_output),
        "mermaid" => MermaidSnippetValidator.new(project, verbose_output)
      }

      # Fallback validator for unknown snippet types
      @fallback_validator = FallbackSnippetValidator.new(project, verbose_output)

      yield project
    end
  end

  def report_results
    puts "\n" + "=" * 60
    puts "📊 VALIDATION SUMMARY"
    puts "=" * 60

    puts "Total snippets validated: #{@total_snippets}"
    puts "Successful: #{@total_snippets - @failures.size}"
    puts "Failed: #{@failures.size}"

    report_failed_snippets if @failures.any?
    report_final_status
  end

  def report_failed_snippets
    puts "\n❌ FAILED SNIPPETS SUMMARY:"
    puts "The following snippets failed validation (details shown above):"
    @failures.each do |failure|
      puts "  • #{failure[:file]} - #{failure[:type]} Snippet ##{failure[:snippet_number]}"
    end
    puts "\n💡 These failures indicate actual issues with the code snippets."
    puts "   Review and fix each snippet to ensure documentation accuracy."
  end

  def report_final_status
    if @failures.empty?
      puts "\n🎉 All snippets validated successfully!"
    end
  end
end
