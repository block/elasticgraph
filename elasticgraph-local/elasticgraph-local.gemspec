# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../elasticgraph-support/lib/elastic_graph/version"

Gem::Specification.new do |spec|
  spec.name = "elasticgraph-local"
  spec.version = ElasticGraph::VERSION
  spec.authors = ["Myron Marston", "Ben VandenBos", "Block Engineering"]
  spec.email = ["myron@squareup.com"]
  spec.homepage = "https://block.github.io/elasticgraph/"
  spec.license = "MIT"
  spec.summary = "Provides support for developing and running ElasticGraph applications locally."

  # See https://guides.rubygems.org/specification-reference/#metadata
  # for metadata entries understood by rubygems.org.
  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/block/elasticgraph/issues",
    "changelog_uri" => "https://github.com/block/elasticgraph/releases/tag/v#{ElasticGraph::VERSION}",
    "documentation_uri" => "https://block.github.io/elasticgraph/docs/v#{ElasticGraph::VERSION}/",
    "homepage_uri" => "https://block.github.io/elasticgraph/",
    "source_code_uri" => "https://github.com/block/elasticgraph/tree/v#{ElasticGraph::VERSION}/#{spec.name}",
    "gem_category" => "local" # used by script/update_codebase_overview
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

  spec.required_ruby_version = [">= 3.2", "< 3.5"]

  spec.add_dependency "elasticgraph-admin", ElasticGraph::VERSION
  spec.add_dependency "elasticgraph-graphql", ElasticGraph::VERSION
  spec.add_dependency "elasticgraph-indexer", ElasticGraph::VERSION
  spec.add_dependency "elasticgraph-rack", ElasticGraph::VERSION
  spec.add_dependency "elasticgraph-schema_definition", ElasticGraph::VERSION
  spec.add_dependency "rackup", "~> 2.2", ">= 2.2.1"
  spec.add_dependency "rake", "~> 13.2", ">= 13.2.1"
  spec.add_dependency "webrick", "~> 1.9", ">= 1.9.1"

  spec.add_development_dependency "elasticgraph-apollo", ElasticGraph::VERSION
  spec.add_development_dependency "elasticgraph-elasticsearch", ElasticGraph::VERSION
  spec.add_development_dependency "elasticgraph-opensearch", ElasticGraph::VERSION
end
