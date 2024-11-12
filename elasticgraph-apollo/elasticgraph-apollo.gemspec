# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../gemspec_helper"

ElasticGraphGemspecHelper.define_elasticgraph_gem(gemspec_file: __FILE__, category: :extension) do |spec, eg_version|
  spec.summary = "An ElasticGraph extension that implements the Apollo federation spec."

  spec.add_dependency "elasticgraph-graphql", eg_version
  spec.add_dependency "elasticgraph-support", eg_version
  spec.add_dependency "graphql", "~> 2.4.3"
  spec.add_dependency "apollo-federation", "~> 3.8"

  # Note: technically, this is not purely a development dependency, but since `eg-schema_def`
  # isn't intended to be used in production (or even included in a deployed bundle) we don't
  # want to declare it as normal dependency here.
  spec.add_development_dependency "elasticgraph-schema_definition", eg_version
  spec.add_development_dependency "elasticgraph-admin", eg_version
  spec.add_development_dependency "elasticgraph-elasticsearch", eg_version
  spec.add_development_dependency "elasticgraph-opensearch", eg_version
  spec.add_development_dependency "elasticgraph-indexer", eg_version
end
