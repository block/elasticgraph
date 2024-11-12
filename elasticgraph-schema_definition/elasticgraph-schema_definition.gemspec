# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../gemspec_helper"

ElasticGraphGemspecHelper.define_elasticgraph_gem(gemspec_file: __FILE__, category: :local) do |spec, eg_version|
  spec.summary = "ElasticGraph gem that provides the schema definition API and generates schema artifacts."

  spec.add_dependency "elasticgraph-graphql", eg_version # needed since we validate that scalar `coerce_with` options are valid (which loads scalar coercion adapters)
  spec.add_dependency "elasticgraph-indexer", eg_version # needed since we validate that scalar `prepare_for_indexing_with` options are valid (which loads indexing preparer adapters)
  spec.add_dependency "elasticgraph-json_schema", eg_version
  spec.add_dependency "elasticgraph-schema_artifacts", eg_version
  spec.add_dependency "elasticgraph-support", eg_version
  spec.add_dependency "graphql", "~> 2.4.3"
  spec.add_dependency "rake", "~> 13.2"

  spec.add_development_dependency "elasticgraph-admin", eg_version
  spec.add_development_dependency "elasticgraph-datastore_core", eg_version
  spec.add_development_dependency "elasticgraph-elasticsearch", eg_version
  spec.add_development_dependency "elasticgraph-opensearch", eg_version
end
