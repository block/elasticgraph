# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/datastore_response/document"
require "elastic_graph/graphql/resolvers/get_record_field_value"

module ElasticGraph
  class GraphQL
    module Resolvers
      RSpec.describe GetRecordFieldValue, :capture_logs, :resolver do
        attr_accessor :schema_artifacts

        before(:context) do
          self.schema_artifacts = generate_schema_artifacts do |schema|
            schema.scalar_type "MyInt" do |t|
              t.mapping type: "integer"
              t.json_schema type: "integer"
            end

            schema.object_type "PersonIdentifiers" do |t|
              t.field "ssn", "String"
            end

            schema.object_type "Person" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.field "identifiers", "PersonIdentifiers"
              t.field "ssn", "String", name_in_index: "identifiers.ssn", graphql_only: true
              t.field "alt_name1", "String", name_in_index: "name", graphql_only: true
              t.field "alt_name2", "String", name_in_index: "name", graphql_only: true
              t.field "converted_type", "MyInt"
              t.field "nicknames", "[String!]"
              t.field "alt_nicknames", "[String!]", name_in_index: "nicknames", graphql_only: true
              t.field "doc_count", "Int"
              t.index "people"
            end
          end
        end

        let(:graphql) { build_graphql(schema_artifacts: schema_artifacts) }

        context "for a field without customizations" do
          it "fetches a requested scalar field from the document" do
            value = resolve(:Person, :name, {"id" => 1, "name" => "Napoleon"})

            expect(value).to eq "Napoleon"
          end

          it "works with an `DatastoreResponse::Document`" do
            doc = DatastoreResponse::Document.with_payload("id" => 1, "name" => "Napoleon")
            value = resolve(:Person, :name, doc)

            expect(value).to eq "Napoleon"
          end

          it "fetches a requested list field from the document" do
            value = resolve(:Person, :nicknames, {"id" => 1, "nicknames" => %w[Napo Leon]})

            expect(value).to eq %w[Napo Leon]
          end

          it "returns `nil` when a scalar field is missing" do
            value = resolve(:Person, :name, {"id" => 1})

            expect(value).to eq nil
          end

          it "returns a blank list when a list field is missing" do
            value = resolve(:Person, :nicknames, {"id" => 2})

            expect(value).to eq []
          end
        end

        context "for a field with customizations" do
          it "resolves to the field named via the `name_in_index` option instead of the schema field name" do
            value = resolve(:Person, :alt_name1, {"id" => 1, "name" => "Napoleon"})

            expect(value).to eq "Napoleon"
          end

          it "can resolve to a child `name_in_index`" do
            value = resolve(:Person, :ssn, {"id" => 1, "identifiers" => {"ssn" => "123-456-7890"}})

            expect(value).to eq "123-456-7890"
          end

          it "can resolve a list field" do
            value = resolve(:Person, :alt_nicknames, {"id" => 1, "nicknames" => %w[Napo Leon]})

            expect(value).to eq %w[Napo Leon]
          end

          it "allows the `name` arg value to be a string or symbol" do
            value1 = resolve(:Person, :alt_name1, {"id" => 1, "name" => "Napoleon"})
            value2 = resolve(:Person, :alt_name2, {"id" => 1, "name" => "Napoleon"})

            expect(value1).to eq "Napoleon"
            expect(value2).to eq "Napoleon"
          end

          it "works with an `DatastoreResponse::Document`" do
            doc = DatastoreResponse::Document.with_payload("id" => 1, "name" => "Napoleon")
            value = resolve(:Person, :alt_name1, doc)

            expect(value).to eq "Napoleon"
          end

          it "returns `nil` for a scalar when the directive field name is missing" do
            value = resolve(:Person, :alt_name1, {"id" => 1})
            expect(value).to eq nil
          end

          it "returns a blank list for a list field when the directive field name is missing" do
            value = resolve(:Person, :alt_nicknames, {"id" => 2})

            expect(value).to eq []
          end
        end
      end
    end
  end
end
