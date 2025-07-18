# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "snippet"
require_relative "snippet_validator"

class DiffSnippetValidator < SnippetValidator
  def validate(snippet)
    if snippet.content.match?(/^-gem "elasticgraph-elasticsearch".*\n^\+gem "elasticgraph-opensearch"/m)
      show_debug_output "Diff snippet assumes the project was bootstrapped with elasticsearch. Apply diffs from `elasticgraph-elasticsearch` to put it into that state."

      # The diff assumes the ElasticGraph project was originally bootstrapped with Elasticsearch.
      # In reality it bootstraps with OpenSearch and we need to swap it over to Elasticsearch before
      # we can apply the diff.
      #
      # We do so using the diff snippets from `elasticgraph-elasticsearch/README.md`.
      Snippet
        .extract_from(::File.expand_path("../../elasticgraph-elasticsearch/README.md", __dir__))
        .select { |s| s.type == "diff" }
        .each { |s| apply_diff(s) }
    end

    apply_diff(snippet) do
      # If it's a `Gemfile` change, run `bundle install`.
      # Otherwise, run `rake` to verify the build still passes.
      if snippet.content.lines.first.strip == "diff --git a/Gemfile b/Gemfile"
        bundle_output = `bundle install 2>&1`

        if $?.success?
          ValidationResult.passed
        else
          ValidationResult.failed("Bundle install failed:\n#{bundle_output}")
        end
      else
        rake_output = `bundle exec rake 2>&1`

        if $?.success?
          ValidationResult.passed
        else
          ValidationResult.failed("Rake failed:\n#{rake_output}")
        end
      end
    end
  end

  private

  def apply_diff(snippet)
    temp_project.in_dir do
      # Create a temporary diff file
      Tempfile.create(["snippet", ".diff"]) do |diff_file|
        diff_file.write(snippet.content)
        diff_file.flush

        # Apply the diff
        apply_output = `git apply #{Shellwords.escape(diff_file.path)} 2>&1`
        unless $?.success?
          return ValidationResult.failed("Failed to apply diff:\n#{apply_output}")
        end

        yield if block_given?
      end
    end
  end
end
