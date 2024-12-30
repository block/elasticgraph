# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "lib/elastic_graph/version"

Gem::Specification.new do |spec|
  spec.name = "elasticgraph-support"
  spec.version = ElasticGraph::VERSION
  spec.authors = ["Myron Marston", "Ben VandenBos", "Block Engineering"]
  spec.email = ["myron@squareup.com"]
  spec.homepage = "https://block.github.io/elasticgraph/"
  spec.license = "MIT"
  spec.summary = "ElasticGraph gem providing support utilities to the other ElasticGraph gems."

  # See https://guides.rubygems.org/specification-reference/#metadata
  # for metadata entries understood by rubygems.org.
  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/block/elasticgraph/issues",
    "changelog_uri" => "https://github.com/block/elasticgraph/releases/tag/v#{ElasticGraph::VERSION}",
    "documentation_uri" => "https://block.github.io/elasticgraph/docs/main/",
    "homepage_uri" => "https://block.github.io/elasticgraph/",
    "source_code_uri" => "https://github.com/block/elasticgraph/tree/v#{ElasticGraph::VERSION}/#{spec.name}",
    "gem_category" => "core" # used by script/update_codebase_overview
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

  # Ruby 3.4 warns about using `logger` being moved out of the standard library, and in Ruby 3.5
  # it'll no longer be available without declaring a dependency.
  #
  # Note: Logger 1.6.0 has an issue that impacts our ElasticGraph lambdas, but 1.6.1 avoids the issue:
  # https://github.com/aws/aws-lambda-ruby-runtime-interface-client/issues/33
  spec.add_dependency "logger", "~> 1.6", ">= 1.6.2"

  spec.add_development_dependency "faraday", "~> 2.12"
  spec.add_development_dependency "rake", "~> 13.2"
end
