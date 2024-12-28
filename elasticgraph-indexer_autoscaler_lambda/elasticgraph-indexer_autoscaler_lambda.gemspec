# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../elasticgraph-support/lib/elastic_graph/version"

Gem::Specification.new do |spec|
  spec.name = "elasticgraph-indexer_autoscaler_lambda"
  spec.version = ElasticGraph::VERSION
  spec.authors = ["Myron Marston", "Ben VandenBos", "Block Engineering"]
  spec.email = ["myron@squareup.com"]
  spec.homepage = "https://block.github.io/elasticgraph/"
  spec.license = "MIT"
  spec.summary = "ElasticGraph gem that monitors OpenSearch CPU utilization to autoscale indexer lambda concurrency."

  # See https://guides.rubygems.org/specification-reference/#metadata
  # for metadata entries understood by rubygems.org.
  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/block/elasticgraph/issues",
    "changelog_uri" => "https://github.com/block/elasticgraph/releases/tag/v#{ElasticGraph::VERSION}",
    "documentation_uri" => "https://block.github.io/elasticgraph/docs/main/",
    "homepage_uri" => "https://block.github.io/elasticgraph/",
    "source_code_uri" => "https://github.com/block/elasticgraph/tree/v#{ElasticGraph::VERSION}/#{spec.name}",
    "gem_category" => "lambda" # used by script/update_codebase_overview
  }

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  # We also remove `.rspec` and `Gemfile` because these files are not needed in
  # the packaged gem (they are for local development of the gems) and cause a problem
  # for some users of the gem due to the fact that they are symlinks to a parent path.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features|sig)/|\.(?:git|travis|circleci)|appveyor)})
    end - [".rspec", "Gemfile", ".yardopts"]
  end

  spec.required_ruby_version = "~> 3.2"

  spec.add_dependency "elasticgraph-datastore_core", ElasticGraph::VERSION
  spec.add_dependency "elasticgraph-lambda_support", ElasticGraph::VERSION
  spec.add_dependency "aws-sdk-lambda", "~> 1.144"
  spec.add_dependency "aws-sdk-sqs", "~> 1.89"
  spec.add_dependency "aws-sdk-cloudwatch", "~> 1.108"
  # aws-sdk-sqs requires an XML library be available. On Ruby < 3 it'll use rexml from the standard library but on Ruby 3.0+
  # we have to add an explicit dependency. It supports ox, oga, libxml, nokogiri or rexml, and of those, ox seems to be the
  # best choice: it leads benchmarks, is well-maintained, has no dependencies, and is MIT-licensed.
  spec.add_dependency "ox", "~> 2.14", ">= 2.14.18"

  spec.add_development_dependency "elasticgraph-elasticsearch", ElasticGraph::VERSION
  spec.add_development_dependency "elasticgraph-opensearch", ElasticGraph::VERSION
end
