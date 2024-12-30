# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../gemspec_helper"

ElasticGraphGemspecHelper.define_elasticgraph_gem(gemspec_file: __FILE__, category: :lambda) do |spec, eg_version|
  spec.summary = "ElasticGraph gem that wraps elasticgraph-graphql in an AWS Lambda."

  spec.add_dependency "elasticgraph-graphql", eg_version
  spec.add_dependency "elasticgraph-lambda_support", eg_version

  spec.add_development_dependency "elasticgraph-elasticsearch", eg_version
  spec.add_development_dependency "elasticgraph-query_registry", eg_version
end
