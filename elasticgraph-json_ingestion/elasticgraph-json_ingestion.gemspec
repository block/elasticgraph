# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../elasticgraph-support/lib/elastic_graph/version"

Gem::Specification.new do |spec|
  spec.name = "elasticgraph-json_ingestion"
  spec.version = ElasticGraph::VERSION
  spec.authors = ["Josh Wilson", "Myron Marston", "Block Engineering"]
  spec.email = ["joshuaw@squareup.com"]
  spec.homepage = "https://block.github.io/elasticgraph/"
  spec.license = "MIT"
  spec.summary = "JSON Schema ingestion support for ElasticGraph."

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

  spec.required_ruby_version = [">= 3.4", "< 4.1"]

  # This gem `prepend`s/`extend`s modules onto `ElasticGraph::SchemaDefinition::API` at runtime, so its
  # code requires `elasticgraph-schema_definition` to be loaded. We declare that as a *development*
  # dependency rather than a runtime dependency to keep the gem-spec dep direction acyclic:
  # `elasticgraph-schema_definition` runtime-depends on this gem (so installing `schema_definition`
  # always pulls in this serializer by default), and this gem's code references `schema_definition` only
  # via paths that are always already loaded by the time this gem is required.
  spec.add_development_dependency "elasticgraph-schema_definition", ElasticGraph::VERSION
  spec.add_dependency "elasticgraph-support", ElasticGraph::VERSION
end
