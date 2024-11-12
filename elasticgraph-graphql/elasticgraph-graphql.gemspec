# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../gemspec_helper"

ElasticGraphGemspecHelper.define_elasticgraph_gem(gemspec_file: __FILE__, category: :core) do |spec, eg_version|
  spec.summary = "The ElasticGraph GraphQL query engine."

  spec.add_dependency "elasticgraph-datastore_core", eg_version
  spec.add_dependency "elasticgraph-schema_artifacts", eg_version
  spec.add_dependency "graphql", "~> 2.4.3"

  spec.add_development_dependency "elasticgraph-admin", eg_version
  spec.add_development_dependency "elasticgraph-elasticsearch", eg_version
  spec.add_development_dependency "elasticgraph-opensearch", eg_version
  spec.add_development_dependency "elasticgraph-indexer", eg_version
  spec.add_development_dependency "elasticgraph-schema_definition", eg_version
end
