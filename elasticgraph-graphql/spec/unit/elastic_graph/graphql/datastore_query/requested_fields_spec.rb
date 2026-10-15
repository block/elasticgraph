# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_unit_support"
require "elastic_graph/graphql/field_retrieval"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "#requested_fields" do
      include_context "DatastoreQueryUnitSupport"

      context "with automatic retrieval" do
        let(:graphql) { build_graphql(experimental_field_retrieval: "automatic") }

        it "replans after merging the complete selection" do
          query = new_query(requested_fields: ["id", "name"])
          expect(datastore_body_of(query)).to include(_source: false, docvalue_fields: ["name"])
          merged = query.merge_with(requested_fields: ["tags"])
          expect(datastore_body_of(merged)).to include(_source: {includes: ["name", "tags"]})
          expect(datastore_body_of(merged)).not_to have_key(:docvalue_fields)
        end
      end

      it "requests only non-id fields from the datastore when building the request body" do
        query = new_query(requested_fields: ["name", "id"])

        expect(datastore_body_of(query)[:_source][:includes]).to contain_exactly("name")
      end

      it "invokes the injected planner lazily with the merged selection and memoizes its plan" do
        planner = instance_double(FieldRetrieval::Source)
        graphql = build_graphql(field_retrieval_planner: planner)
        query = graphql.datastore_query_builder.new_query(
          initial_search_index_definitions: graphql.datastore_core.index_definitions_by_graphql_type.fetch("Widget"),
          requested_fields: ["name"]
        )
        merged = query.merge_with(requested_fields: ["workspace_id2"])
        expect(planner).to receive(:plan).once.with(
          requested_fields: ["name", "workspace_id2"], request_all_fields: false, highlighting: false,
          index_definitions: query.narrowed_search_index_definitions
        ).and_return(FieldRetrievalPlan::SOURCE)

        expect(datastore_body_of(merged)).to include(_source: true)
        expect(merged.field_retrieval_plan).to be(FieldRetrievalPlan::SOURCE)
      end

      it "requests all fields in requested_fields when requested_fields does not include id" do
        query = new_query(requested_fields: ["name", "age"])

        expect(datastore_body_of(query)[:_source][:includes]).to contain_exactly("name", "age")
      end

      it "does not request _source when id is the only requested field" do
        query = new_query(requested_fields: ["id"])

        expect(datastore_body_of(query)[:_source]).to eq(false)
      end

      it "does not request _source when no fields are requested" do
        query = new_query(requested_fields: [])

        expect(datastore_body_of(query)[:_source]).to eq(false)
      end

      it "passes `_source: true` when requesting all fields" do
        query = new_query(requested_fields: [], request_all_fields: true)

        expect(datastore_body_of(query)[:_source]).to eq(true)
      end
    end
  end
end
