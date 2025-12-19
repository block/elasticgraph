# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../elasticgraph-support/lib/elastic_graph/version"

Gem::Specification.new do |spec|
  spec.name = "elasticgraph-warehouse"
  spec.version = ElasticGraph::VERSION
  spec.authors = ["Josh Wilson", "Block Engineering"]
  spec.email = ["joshuaw@squareup.com"]
  spec.homepage = "https://block.github.io/elasticgraph/"
  spec.license = "MIT"
  spec.summary = "Extends ElasticGraph to support ingestion into a data warehouse."

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/block/elasticgraph/issues",
    "changelog_uri" => "https://github.com/block/elasticgraph/releases/tag/v#{ElasticGraph::VERSION}",
    "documentation_uri" => "https://block.github.io/elasticgraph/api-docs/v#{ElasticGraph::VERSION}/",
    "homepage_uri" => "https://block.github.io/elasticgraph/",
    "source_code_uri" => "https://github.com/block/elasticgraph/tree/v#{ElasticGraph::VERSION}/#{spec.name}",
    "gem_category" => "extension"
  }

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features|sig)/|\.(?:git|travis|circleci)|appveyor)})
    end - [".rspec", "Gemfile", ".yardopts"]
  end

  spec.required_ruby_version = [">= 3.4", "< 3.5"]

  spec.add_dependency "elasticgraph-support", ElasticGraph::VERSION

  # Lambda-related dependencies (for warehouse lambda functionality)
  spec.add_dependency "elasticgraph-indexer_lambda", ElasticGraph::VERSION
  spec.add_dependency "elasticgraph-lambda_support", ElasticGraph::VERSION
  spec.add_dependency "aws-sdk-s3", "~> 1.208"

  # aws-sdk-s3 requires an XML library be available. On Ruby < 3 it'll use rexml from the standard library but on Ruby 3.0+
  # we have to add an explicit dependency. It supports ox, oga, libxml, nokogiri or rexml, and of those, ox seems to be the
  # best choice: it leads benchmarks, is well-maintained, has no dependencies, and is MIT-licensed.
  spec.add_dependency "ox", "~> 2.14", ">= 2.14.23"

  spec.add_development_dependency "elasticgraph-schema_definition", ElasticGraph::VERSION
end
