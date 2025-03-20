# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql"
require "elastic_graph/query_registry/variable_dumper"

module ElasticGraph
  module QueryRegistry
    RSpec.describe VariableDumper do
      let(:dumper) { VariableDumper.new(build_graphql.schema.graphql_schema) }

      describe "#dump_variables_for_query" do
        it "returns an empty hash for a valid query that has no variables" do
          query_string = <<~EOS
            query MyQuery {
              widgets {
                total_edge_count
              }
            }
          EOS

          expect(dumper.dump_variables_for_query(query_string)).to eq({"MyQuery" => {}})
        end

        it "returns an empty hash for an unparsable query that has variables" do
          query_string = <<~EOS
            query MyQuery($idFilter: IDFilterInput!) {
              widgets(filter: {id: $idFilter}) # missing a curly brace here
                total_edge_count
              }
            }
          EOS

          expect(dumper.dump_variables_for_query(query_string)).to eq({})
        end

        it "includes a simple type entry for each scalar or list-of-scalar variable" do
          query_string = <<~EOS
            query CountWidgetAndAddress($id: ID!, $addressId: ID) {
              widgets(filter: {id: {equal_to_any_of: [$id]}}) {
                total_edge_count
              }

              addresses(filter: {id: {equal_to_any_of: [$addressId]}}){
                total_edge_count
              }
            }

            query AnotherQuery($ids: [ID!]) {
              components(filter: {id: {equal_to_any_of: $ids}}) {
                total_edge_count
              }
            }
          EOS

          expect(dumper.dump_variables_for_query(query_string)).to eq({
            "CountWidgetAndAddress" => {"id" => "ID!", "addressId" => "ID"},
            "AnotherQuery" => {"ids" => "[ID!]"}
          })
        end

        it "provides a reasonable default name for operations that lack names" do
          query_string = <<~EOS
            query {
              widgets {
                total_edge_count
              }
            }
          EOS

          expect(dumper.dump_variables_for_query(query_string)).to eq({
            "(Anonymous operation 1)" => {}
          })
        end

        it "includes `values` for enum variables" do
          query_string = <<~EOS
            query CountWithColorFilterInput($colors: [Color!]) {
              widgets(filter: {options: {color: {equal_to_any_of: $colors}}}) {
                total_edge_count
              }
            }
          EOS

          expect(dumper.dump_variables_for_query(query_string)).to eq({
            "CountWithColorFilterInput" => {
              "colors" => {"type" => "[Color!]", "values" => ["BLUE", "GREEN", "RED"]}
            }
          })
        end

        it "includes the `fields` for an object variable" do
          query_string = <<~EOS
            query CountWithIdFilterInput($idFilter: IDFilterInput!) {
              widgets(filter: {id: $idFilter}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
          EOS

          expect(dumper.dump_variables_for_query(query_string)).to eq({
            "CountWithIdFilterInput" => {
              "idFilter" => {
                "type" => "IDFilterInput!",
                "fields" => {"any_of" => "[IDFilterInput!]", "not" => "IDFilterInput", "equal_to_any_of" => "[ID]"}
              }
            }
          })
        end

        it "just includes the type name for variables that reference undefined types" do
          query_string = <<~EOS
            query FindWidgets($id1: Identifier!, $id2: ID!) {
              widgets(filter: {id: {equal_to_any_of: [$id1, $id2]}}) {
                total_edge_count
              }
            }
          EOS

          expect(dumper.dump_variables_for_query(query_string)).to eq({
            "FindWidgets" => {
              "id1" => "Identifier!",
              "id2" => "ID!"
            }
          })
        end

        it "handles nested objects" do
          query_string = <<~EOS
            query CountWithOptions($optionsFilterInput: WidgetOptionsFilterInput!) {
              widgets(filter: {options: $optionsFilterInput}) {
                total_edge_count
              }
            }
          EOS

          expect(dumper.dump_variables_for_query(query_string)).to eq({"CountWithOptions" => {
            "optionsFilterInput" => {"type" => "WidgetOptionsFilterInput!", "fields" => {
              "any_of" => "[WidgetOptionsFilterInput!]",
              "not" => "WidgetOptionsFilterInput",
              "color" => {"type" => "ColorFilterInput", "fields" => {
                "any_of" => "[ColorFilterInput!]",
                "not" => "ColorFilterInput",
                "equal_to_any_of" => {"type" => "[ColorInput]", "values" => ["BLUE", "GREEN", "RED"]}
              }},
              "is_draft" => {"type" => "BooleanFilterInput", "fields" => {
                "any_of" => "[BooleanFilterInput!]",
                "not" => "BooleanFilterInput",
                "equal_to_any_of" => "[Boolean]"
              }},
              "size" => {"type" => "SizeFilterInput", "fields" => {
                "any_of" => "[SizeFilterInput!]",
                "not" => "SizeFilterInput",
                "equal_to_any_of" => {"type" => "[SizeInput]", "values" => ["LARGE", "MEDIUM", "SMALL"]}
              }},
              "the_size" => {"type" => "SizeFilterInput", "fields" => {
                "any_of" => "[SizeFilterInput!]",
                "not" => "SizeFilterInput",
                "equal_to_any_of" => {"type" => "[SizeInput]", "values" => ["LARGE", "MEDIUM", "SMALL"]}
              }}
            }}
          }})
        end

        it "ignores fragments" do
          query_string = <<~EOS
            query CountWidgetAndAddress($id: ID!) {
              widgets(filter: {id: {equal_to_any_of: [$id]}}) {
                ...widgetsFields
              }
            }

            fragment widgetsFields on WidgetConnection {
              total_edge_count
            }
          EOS

          expect(dumper.dump_variables_for_query(query_string)).to eq({
            "CountWidgetAndAddress" => {"id" => "ID!"}
          })
        end
      end
    end
  end
end
