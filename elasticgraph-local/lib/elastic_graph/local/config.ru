# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This `config.ru` file is used by the `rake boot_graphiql` task.

require "elastic_graph/graphql"
require "elastic_graph/graphiql"

graphql = ElasticGraph::GraphQL.from_yaml_file(ENV.fetch("ELASTICGRAPH_YAML_FILE"))
run ElasticGraph::GraphiQL.new(graphql)
