# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_unit_support"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "#requested_fields" do
      include_context "DatastoreQueryUnitSupport"

      it "requests only non-id fields from the datastore when building the request body" do
        query = new_query(requested_fields: ["name", "id"])

        expect(datastore_body_of(query)[:_source][:includes]).to contain_exactly("name")
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

      it "still requests doc values when requesting all fields" do
        graphql = build_graphql(schema_definition: lambda do |schema|
          schema.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "name", "String"
            t.field "internal_code", "String", retrieved_from: :doc_values
            t.index "widgets"
          end
        end)
        query = graphql.datastore_query_builder.new_query(
          search_index_definitions: graphql.datastore_core.index_definitions_by_graphql_type.fetch("Widget"),
          request_all_fields: true
        )

        expect(datastore_body_of(query)[:_source]).to eq true
        expect(datastore_body_of(query)[:docvalue_fields]).to contain_exactly("internal_code")
      end

      it "still requests doc values when requesting all fields from mixed index definitions" do
        graphql = build_graphql(schema_definition: lambda do |schema|
          schema.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "internal_code", "String", retrieved_from: :doc_values
            t.index "widgets"
          end
        end)
        doc_values_index_def = graphql.datastore_core.index_definitions_by_name.fetch("widgets")
        source_backed_index_def = doc_values_index_def.with(
          fields_by_path: doc_values_index_def.fields_by_path.merge(
            "internal_code" => doc_values_index_def.fields_by_path.fetch("internal_code").with(retrieved_from: nil)
          )
        )
        query = graphql.datastore_query_builder.new_query(
          search_index_definitions: [doc_values_index_def, source_backed_index_def],
          request_all_fields: true
        )

        expect(datastore_body_of(query)[:_source]).to eq true
        expect(datastore_body_of(query)[:docvalue_fields]).to contain_exactly("internal_code")
      end

      it "requests doc values for fields marked `retrieved_from: :doc_values`" do
        graphql = build_graphql(schema_definition: lambda do |schema|
          schema.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "name", "String"
            t.field "internal_code", "String", retrieved_from: :doc_values
            t.index "widgets"
          end
        end)
        query = graphql.datastore_query_builder.new_query(
          search_index_definitions: graphql.datastore_core.index_definitions_by_graphql_type.fetch("Widget"),
          requested_fields: ["internal_code", "name"]
        )

        expect(datastore_body_of(query)[:docvalue_fields]).to contain_exactly("internal_code")
        expect(datastore_body_of(query)[:_source][:includes]).to contain_exactly("name")
      end

      it "keeps requesting `_source` when index definitions disagree on how to retrieve a field" do
        graphql = build_graphql(schema_definition: lambda do |schema|
          schema.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "internal_code", "String", retrieved_from: :doc_values
            t.index "widgets"
          end
        end)
        doc_values_index_def = graphql.datastore_core.index_definitions_by_name.fetch("widgets")
        source_backed_index_def = doc_values_index_def.with(
          fields_by_path: doc_values_index_def.fields_by_path.merge(
            "internal_code" => doc_values_index_def.fields_by_path.fetch("internal_code").with(retrieved_from: nil)
          )
        )
        query = graphql.datastore_query_builder.new_query(
          search_index_definitions: [doc_values_index_def, source_backed_index_def],
          requested_fields: ["internal_code"]
        )

        expect(datastore_body_of(query)[:docvalue_fields]).to eq nil
        expect(datastore_body_of(query)[:_source][:includes]).to contain_exactly("internal_code")
      end
    end
  end
end
