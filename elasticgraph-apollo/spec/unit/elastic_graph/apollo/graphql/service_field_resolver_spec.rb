# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/apollo/graphql/engine_extension"
require "elastic_graph/apollo/graphql/service_field_resolver"
require "elastic_graph/graphql"
require "elastic_graph/graphql/datastore_response/search_response"

module ElasticGraph
  module Apollo
    module GraphQL
      RSpec.describe ServiceFieldResolver, :builds_graphql do
        before do
          allow(datastore_client).to receive(:msearch).and_return(
            {"responses" => [ElasticGraph::GraphQL::DatastoreResponse::SearchResponse::RAW_EMPTY]}
          )
        end

        let(:graphql) do
          build_graphql(
            schema_artifacts_directory: "config/schema/artifacts_with_apollo",
            extension_modules: [EngineExtension]
          )
        end

        it "returns the SDL string of the schema as per the Apollo federation v2 spec" do
          data = execute_expecting_no_errors("query { _service { sdl } }")
          expect(data).to match("_service" => {"sdl" => an_instance_of(::String)})

          returned_schema = ::GraphQL::Schema.from_definition(data.fetch("_service").fetch("sdl"))
          full_schema = graphql.schema.graphql_schema

          expect(full_schema.types.keys).to match_array(returned_schema.types.keys)
          expect(full_schema.types.fetch("Query").fields.keys).to match_array(returned_schema.types.fetch("Query").fields.keys)
        end

        it "does not interfere with other fields on the `Query` type" do
          data = execute_expecting_no_errors("query { widgets { total_edge_count } }")

          expect(data).to eq("widgets" => {"total_edge_count" => 0})
        end

        def execute_expecting_no_errors(query, **options)
          response = graphql.graphql_query_executor.execute(query, **options)
          expect(response["errors"]).to be nil
          response.fetch("data")
        end
      end
    end
  end
end
