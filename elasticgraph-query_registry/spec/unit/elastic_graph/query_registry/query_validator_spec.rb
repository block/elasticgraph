# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql"
require "elastic_graph/query_registry/query_validator"
require "elastic_graph/query_registry/variable_dumper"

module ElasticGraph
  module QueryRegistry
    RSpec.describe QueryValidator do
      let(:schema) { build_graphql.schema }
      let(:variable_dumper) { VariableDumper.new(schema.graphql_schema) }

      describe "#validate" do
        it "returns no errors when given a valid named query with no arguments" do
          query_string = <<~EOS
            query MyQuery {
              widgets {
                total_edge_count
              }
            }
          EOS

          expect(validate(query_string)).to eq("MyQuery" => [])
        end

        it "allows fragments to be used in queries" do
          query_string = <<~EOS
            query MyQuery {
              widgets {
                ...widgetsFields
              }
            }

            fragment widgetsFields on WidgetConnection {
              total_edge_count
            }
          EOS

          expect(validate(query_string)).to eq("MyQuery" => [])
        end

        it "returns errors when a fragment is defined but not used" do
          query_string = <<~EOS
            query MyQuery {
              widgets {
                total_edge_count
              }
            }

            fragment widgetsFields on WidgetConnection {
              total_edge_count
            }
          EOS

          expect(validate(query_string)).to have_errors_for_operations("MyQuery" => [{
            "message" => "Fragment widgetsFields was defined, but not used"
          }])
        end

        it "returns errors when given a valid unnamed query with no arguments, since we want all queries to be named for better logging" do
          query_string = <<~EOS
            query {
              widgets {
                total_edge_count
              }
            }
          EOS

          expect(validate(query_string)).to have_errors_for_operations(nil => [{
            "message" => a_string_including("no named operations")
          }])
        end

        it "returns errors when the query cannot be parsed" do
          query_string = <<~EOS
            query MyQuery bad syntax {
              widgets {
                total_edge_count
              }
            }
          EOS

          expect(validate(query_string)).to have_errors_for_operations(nil => [{
            "locations" => [{"line" => 1, "column" => 15}],
            "message" => a_string_including("Expected LCURLY, actual: IDENTIFIER (\"bad\")")
          }])
        end

        it "returns errors when the query string is empty" do
          expect(validate("")).to have_errors_for_operations(nil => [{
            "message" => a_string_including("Unexpected end of document")
          }])
        end

        it "returns errors when the query references undefined fields" do
          query_string = <<~EOS
            query MyQuery {
              widgets {
                not_a_real_field
              }
            }
          EOS

          expect(validate(query_string)).to have_errors_for_operations("MyQuery" => [{
            "locations" => [{"line" => 3, "column" => 5}],
            "message" => a_string_including("not_a_real_field"),
            "path" => ["query MyQuery", "widgets", "not_a_real_field"]
          }])
        end

        it "returns errors when the query references an undefined field input argument" do
          query_string = <<~EOS
            query MyQuery {
              widgets(filter: {not_a_field: {equal_to_any_of: [1]}}) {
                total_edge_count
              }
            }
          EOS

          expect(validate(query_string)).to have_errors_for_operations("MyQuery" => [{
            "locations" => [{"line" => 2, "column" => 20}],
            "message" => a_string_including("not_a_field"),
            "path" => ["query MyQuery", "widgets", "filter", "not_a_field"]
          }])
        end

        context "when the `@eg_latency_slo` directive is required" do
          it "returns an error if the query lacks an `@eg_latency_slo` directive" do
            query_string = <<~EOS
              query MyQuery {
                widgets {
                  total_edge_count
                }
              }
            EOS

            expect(validate(query_string)).to have_errors_for_operations("MyQuery" => [{
              "message" => "Your `MyQuery` operation is missing the required `@eg_latency_slo(ms: Int!)` directive."
            }])
          end

          it "does not return an error if the query has an `@eg_latency_slo` directive" do
            query_string = <<~EOS
              query MyQuery @eg_latency_slo(ms: 5000) {
                widgets {
                  total_edge_count
                }
              }
            EOS

            expect(validate(query_string)).to eq("MyQuery" => [])
          end

          def validate(query_string)
            super(query_string, require_eg_latency_slo_directive: true)
          end
        end

        context "when the `@eg_latency_slo` directive is not required" do
          it "does still allows the query to have an `@eg_latency_slo` directive" do
            query_string = <<~EOS
              query MyQuery @eg_latency_slo(ms: 5000) {
                widgets {
                  total_edge_count
                }
              }
            EOS

            expect(validate(query_string)).to eq("MyQuery" => [])
          end

          def validate(query_string)
            super(query_string, require_eg_latency_slo_directive: false)
          end
        end

        context "when the query contains multiple operations" do
          it "returns no errors if each is individually valid" do
            query_string = <<~EOS
              query MyQuery1 {
                widgets {
                  total_edge_count
                }
              }

              query MyQuery2 {
                components {
                  total_edge_count
                }
              }
            EOS

            expect(validate(query_string)).to eq("MyQuery1" => [], "MyQuery2" => [])
          end

          it "validates each individual operation and returns the errors for each" do
            query_string = <<~EOS
              query InvalidField {
                widgets {
                  foo
                }
              }

              query ValidQuery {
                widgets {
                  total_edge_count
                }
              }

              query InvalidArg {
                components(foo: 1) {
                  total_edge_count
                }
              }
            EOS

            expect(validate(query_string)).to have_errors_for_operations(
              "InvalidField" => [{"message" => a_string_including("foo")}],
              "ValidQuery" => [],
              "InvalidArg" => [{"message" => a_string_including("foo")}]
            )
          end
        end

        context "when no `previously_dumped_variables` information is available" do
          it "returns an error telling the engineer to run the rake task to dump them" do
            query_string = <<~EOS
              query MyQuery {
                widgets {
                  total_edge_count
                }
              }
            EOS

            expect(validate(query_string, previously_dumped_variables: nil, client_name: "Bob", query_name: "MyQ")).to have_errors_for_operations("MyQuery" => [{
              "message" => a_string_including("No dumped variables", "query_registry:dump_variables[Bob, MyQ]")
            }])
          end
        end

        context "when the query has arguments" do
          it "still validates correctly in spite of us providing no values for required args" do
            query_string = <<~EOS
              query FindWidgetGood($id: ID!) {
                widgets(filter: {id: {equal_to_any_of: [$id]}}) {
                  edges {
                    node {
                      id
                    }
                  }
                }
              }

              query FindWidgetBad($id: ID!) {
                widgets(filter: {id: {equal_to_any_of: [$id]}}) {
                  edges {
                    node {
                      id
                      not_a_field
                    }
                  }
                }
              }
            EOS

            expect(validate(query_string)).to have_errors_for_operations(
              "FindWidgetGood" => [],
              "FindWidgetBad" => [{"message" => a_string_including("not_a_field")}]
            )
          end

          it "returns errors if a variable references an unknown type" do
            query_string = <<~EOS
              query FindWidget($id: Identifier) {
                widgets(filter: {id: {equal_to_any_of: [$id]}}) {
                  total_edge_count
                }
              }
            EOS

            expect(validate(query_string)).to have_errors_for_operations(
              "FindWidget" => [{
                "message" => a_string_including("Identifier isn't a defined input type"),
                "path" => ["query FindWidget"],
                "extensions" => {
                  "code" => "variableRequiresValidType",
                  "variableName" => "id",
                  "typeName" => "Identifier"
                },
                "locations" => [{"line" => 1, "column" => 18}]
              }]
            )
          end

          it "returns errors if a variable name is malformed" do
            query_string = <<~EOS
              query FindWidget(id: ID) {
                widgets(filter: {id: {equal_to_any_of: [$id]}}) {
                  total_edge_count
                }
              }
            EOS

            expect(validate(query_string)).to have_errors_for_operations(nil => [{
              "locations" => [{"line" => 1, "column" => 18}],
              "message" => a_string_including("Expected VAR_SIGN, actual: IDENTIFIER (\"id\")")
            }])
          end

          it "allows variables to be any non-object type (including scalars, lists, enums, lists-of-those, etc)" do
            query_string = <<~EOS
              query FindWidgets(
                $id1: ID!,
                $ids2: [ID!],
                $ids3: [ID!]!,
                $order_by: WidgetSortOrderInput!
              ) {
                w1: widgets(filter: {id: {equal_to_any_of: [$id1]}}) {
                  total_edge_count
                }

                w2: widgets(filter: {id: {equal_to_any_of: $ids2}}) {
                  total_edge_count
                }

                w3: widgets(filter: {id: {equal_to_any_of: $ids3}}) {
                  total_edge_count
                }

                ordered: widgets(order_by: [$order_by]) {
                  total_edge_count
                }
              }
            EOS

            expect(validate(query_string)).to eq("FindWidgets" => [])
          end

          it "allows all kinds of variables, including objects" do
            query_string = <<~EOS
              query FindWidgets(
                $filter1: WidgetFilterInput,
                $filter2: WidgetFilterInput!,
              ) {
                w1: widgets(filter: $filter1) {
                  total_edge_count
                }

                w2: widgets(filter: $filter2) {
                  total_edge_count
                }
              }
            EOS

            expect(validate(query_string)).to eq("FindWidgets" => [])
          end

          context "when the variable types have changed in a backwards-compatible way" do
            it "tells the user to re-run the dump rake task to update the file" do
              old_query_string = <<~EOS
                query FindWidgets($id: ID!) {
                  widgets(filter: {id: {equal_to_any_of: [$id]}}) {
                    edges {
                      node {
                        id
                      }
                    }
                  }
                }
              EOS
              previously_dumped_variables = variable_dumper.dump_variables_for_query(old_query_string)

              new_query_string = <<~EOS
                query FindWidgets($id: ID!, $first: Int) {
                  widgets(filter: {id: {equal_to_any_of: [$id]}}, first: $first) {
                    edges {
                      node {
                        id
                      }
                    }
                  }
                }
              EOS
              errors = validate(new_query_string, previously_dumped_variables: previously_dumped_variables, client_name: "C1", query_name: "Q1")

              expect(errors).to have_errors_for_operations("FindWidgets" => [{"message" => a_string_including(
                "variables file is out-of-date",
                "should not impact `C1`",
                'rake "query_registry:dump_variables[C1, Q1]"'
              )}])
            end
          end

          context "when the variable types have changed in a backwards-incompatible way" do
            it "surfaces the incompatibilities and tells the user to re-run the dump rake task after verifying with the client" do
              old_query_string = <<~EOS
                query FindWidgets($id: ID!) {
                  widgets(filter: {id: {equal_to_any_of: [$id]}}) {
                    edges {
                      node {
                        id
                      }
                    }
                  }
                }
              EOS
              previously_dumped_variables = variable_dumper.dump_variables_for_query(old_query_string)

              new_query_string = <<~EOS
                query FindWidgets($id: ID!, $first: Int!, $cursor: Cursor!) {
                  widgets(filter: {id: {equal_to_any_of: [$id]}}, first: $first, after: $cursor) {
                    edges {
                      node {
                        id
                      }
                    }
                  }
                }
              EOS
              errors = validate(new_query_string, previously_dumped_variables: previously_dumped_variables, client_name: "C1", query_name: "Q1")

              expect(errors).to have_errors_for_operations("FindWidgets" => [{"message" => a_string_including(
                "backwards-incompatible changes that may break `C1`",
                "$cursor (new required variable), $first (new required variable)",
                'rake "query_registry:dump_variables[C1, Q1]"'
              )}])
            end
          end

          context "when the operation name has changed since the last time variables were dumped" do
            it "tells the user to re-dump the variables" do
              old_query_string = <<~EOS
                query findWidgets($id: ID!) {
                  widgets(filter: {id: {equal_to_any_of: [$id]}}) {
                    edges {
                      node {
                        id
                      }
                    }
                  }
                }
              EOS
              previously_dumped_variables = variable_dumper.dump_variables_for_query(old_query_string)

              new_query_string = old_query_string.sub("findWidgets", "FindWidgets")
              result = validate(new_query_string, previously_dumped_variables: previously_dumped_variables, client_name: "bob", query_name: "FindWidgets")

              expect(result).to have_errors_for_operations("FindWidgets" => [{
                "message" => a_string_including("No dumped variables", "query_registry:dump_variables[bob, FindWidgets]")
              }])
            end
          end
        end

        def validate(
          query_string,
          previously_dumped_variables: variable_dumper.dump_variables_for_query(query_string),
          client_name: "MyClient",
          query_name: "MyQuery",
          require_eg_latency_slo_directive: false
        )
          validator = QueryValidator.new(schema, require_eg_latency_slo_directive: require_eg_latency_slo_directive)

          validator.validate(
            query_string,
            previously_dumped_variables: previously_dumped_variables,
            client_name: client_name,
            query_name: query_name
          )
        end

        def have_errors_for_operations(errors_by_op_name)
          matcher_hash = errors_by_op_name.transform_values do |errors|
            a_collection_containing_exactly(*errors.map { |e| a_hash_including(e) })
          end

          match(matcher_hash)
        end
      end
    end
  end
end
