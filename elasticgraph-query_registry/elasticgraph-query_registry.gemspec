# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../gemspec_helper"

ElasticGraphGemspecHelper.define_elasticgraph_gem(gemspec_file: __FILE__, category: :extension) do |spec, eg_version|
  spec.summary = "An ElasticGraph extension that supports safer schema evolution by limiting GraphQL queries based on " \
    "a registry and validating registered queries against the schema."

  spec.add_dependency "elasticgraph-graphql", eg_version
  spec.add_dependency "elasticgraph-support", eg_version
  spec.add_dependency "graphql", "~> 2.4.3"
  spec.add_dependency "rake", "~> 13.2"

  spec.add_development_dependency "elasticgraph-elasticsearch", eg_version
  spec.add_development_dependency "elasticgraph-opensearch", eg_version
end
