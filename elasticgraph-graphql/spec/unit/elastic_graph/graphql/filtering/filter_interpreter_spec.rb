# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/filtering/filter_interpreter"

module ElasticGraph
  class GraphQL
    module Filtering
      # Note: most `FilterInterpreter` logic is driven via the `DatastoreQuery` interface. Here we have only
      # a couple tests that focus on details that don't impact `DatastoreQuery` behavior.
      RSpec.describe FilterInterpreter do
        let(:graphql) { build_graphql }

        it "inspects nicely" do
          fi = graphql.filter_interpreter

          expect(fi.inspect.length).to be < 200
          expect(fi.to_s.length).to be < 200
        end

        specify "two instances are equal when instantiated with the same args" do
          fi1 = FilterInterpreter.new(
            filter_node_interpreter: graphql.filter_node_interpreter,
            logger: graphql.logger
          )

          fi2 = FilterInterpreter.new(
            filter_node_interpreter: graphql.filter_node_interpreter,
            logger: graphql.logger
          )

          expect(fi1).to eq(fi2)
        end
      end
    end
  end
end
