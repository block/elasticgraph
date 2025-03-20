# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

ElasticGraph.define_schema do |schema|
  schema.json_schema_version 1
end

# Note: anytime you add a file to load here, you'll also have to update the list here:
# elasticgraph-graphql/spec/acceptance/elasticgraph_graphql_acceptance_support.rb
load File.join(__dir__, "schema/teams.rb")
load File.join(__dir__, "schema/widgets.rb")
