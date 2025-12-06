# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/query_executor"
require "elastic_graph/graphql/schema"
require "elastic_graph/support/monotonic_clock"

module ElasticGraph
  class GraphQL
    RSpec.describe QueryExecutor do
      describe "#execute", :capture_logs do
        attr_accessor :schema_artifacts

        before(:context) do
          self.schema_artifacts = generate_schema_artifacts do |s|
            s.object_type "Color" do |t|
              t.root_query_fields plural: "ignored"
              t.field "id", "ID"
              t.field "red", "Int"
              t.field "green", "Int"
              t.field "blue", "Int"
              t.index "colors"
            end

            s.object_type "Color2" do |t|
              t.field "id", "ID"
              t.field "red", "Int"
              t.field "green", "Int"
              t.field "blue", "Int"
              t.field "float", "Float"  # so the Float type exists
              t.index "alt_colors"
            end

            s.factory.new_input_type "ColorArgs" do |t|
              t.field "red", "Int"
              s.state.register_input_type(t)
            end

            s.on_built_in_types do |type|
              if type.name == "Query"
                type.field "colors", "[Color!]!" do |f|
                  f.argument "args", "ColorArgs"
                  f.resolve_with :list_records
                end
                type.field "colors2", "[Color2!]!" do |f|
                  f.argument "args", "ColorArgs"
                  f.resolve_with :list_records
                end
              end
            end
          end
        end

        let(:monotonic_clock) { instance_double(Support::MonotonicClock, now_in_ms: monontonic_now_time) }
        let(:monontonic_now_time) { 100_000 }
        let(:slow_query_threshold_ms) { 4000 }
        let(:datastore_query_client_duration_ms) { 75 }
        let(:datastore_query_server_duration_ms) { 50 }
        let(:queried_shard_count) { 17 }
        let(:query_executor) { define_query_executor }

        it "executes the provided query and logs how long it took, including the query fingerprint, and some datastore query details" do
          allow(monotonic_clock).to receive(:now_in_ms).and_return(100, 340)

          # Here we query two different indexes so that we have the same routing values and index expressions,
          # so that we can demonstrate below that it logs the unique values.
          data = execute_expecting_no_errors(<<-QUERY, client: Client.new(name: "client-name", source_description: "client-description"), operation_name: "GetColors")
            query GetColors {
              red: colors(args: {red: 12}) {
                red
              }

              green: colors(args: {red: 13}) {
                green
              }

              blue: colors2(args: {red: 6}) {
                blue
              }
            }
          QUERY

          expect(data).to eq("red" => [], "green" => [], "blue" => [])

          expect(logged_duration_message).to include(
            "client" => "client-name",
            "query_name" => "GetColors",
            "duration_ms" => 240,
            "datastore_server_duration_ms" => datastore_query_server_duration_ms,
            "elasticgraph_overhead_ms" => 240 - datastore_query_client_duration_ms,
            "datastore_request_transport_duration_ms" => datastore_query_client_duration_ms - datastore_query_server_duration_ms,
            "queried_shard_count" => queried_shard_count,
            "unique_shard_routing_values" => "routing_value_1, routing_value_2",
            "unique_shard_routing_value_count" => 2,
            "unique_search_index_expressions" => "alt_colors, colors",
            "datastore_query_count" => 3,
            "datastore_request_count" => 1,
            "over_slow_threshold" => "false",
            "query_fingerprint" => a_string_starting_with("GetColors/")
          )
        end

        it "does not log a duration message when loading dependencies eagerly to avoid skewing metrics derived from the logged messages" do
          define_graphql.load_dependencies_eagerly

          expect(logged_duration_message).to be nil
        end

        it "includes `slo_result: 'good'` in the logged duration message if the query took less than the `@egLatencySlo` directive's value" do
          slo_result = logged_slo_result_for(<<~QUERY, duration_in_ms: 2999)
            query GetColors @eg_latency_slo(ms: 3000) {
              colors(args: {red: 12}) {
                red
              }
            }
          QUERY

          expect(slo_result).to eq("good")
        end

        it "includes `slo_result: 'good'` in the logged duration message if the query took exactly the `@egLatencySlo` directive's value" do
          slo_result = logged_slo_result_for(<<~QUERY, duration_in_ms: 3000)
            query GetColors @eg_latency_slo(ms: 3000) {
              colors(args: {red: 12}) {
                red
              }
            }
          QUERY

          expect(slo_result).to eq("good")
        end

        it "includes `slo_result: false` in the logged duration message if the query took more than the `@egLatencySlo` directive's value" do
          slo_result = logged_slo_result_for(<<~QUERY, duration_in_ms: 3001)
            query GetColors @eg_latency_slo(ms: 3000) {
              colors(args: {red: 12}) {
                red
              }
            }
          QUERY

          expect(slo_result).to eq("bad")
        end

        it "includes `slo_result: nil` in the logged duration message if the query lacks an `@egLatencySlo` directive" do
          slo_result = logged_slo_result_for(<<~QUERY, duration_in_ms: 3001)
            query GetColors {
              colors(args: {red: 12}) {
                red
              }
            }
          QUERY

          expect(slo_result).to eq(nil)
        end

        it "logs the full sanitized query if it took longer than our configured slow query threshold" do
          allow(monotonic_clock).to receive(:now_in_ms).and_return(100, 101 + slow_query_threshold_ms)

          expect {
            data = execute_expecting_no_errors(<<-QUERY, operation_name: "GetColorName")
              query GetColorName {
                __type(name: "Color") {
                  name
                }
              }
            QUERY

            expect(data).to eq("__type" => {"name" => "Color"})
          }.to log a_string_including("longer (4001 ms) than the configured slow query threshold (4000 ms)", <<~EOS.strip)
            query GetColorName {
              __type(name: "<REDACTED>") {
                name
              }
            }
          EOS
        end

        it "logs the full sanitized query with exception details if executing the query triggers an exception" do
          self.schema_artifacts = generate_schema_artifacts do |schema|
            schema.on_root_query_type do |t|
              t.resolve_fields_with nil
              t.field "foo", "Int" do |f|
                f.resolve_with :list_records
              end
            end
          end

          query_string = <<~EOS
            query Foo {
              foo
            }
          EOS

          expect {
            execute_expecting_no_errors(query_string)
          }.to raise_error(a_string_including("Query is invalid, since it contains no `search_index_definitions`."))
            .and log a_string_including(
              "Query Foo[1] for client (anonymous) failed with an exception[2]",
              query_string.to_s,
              "ElasticGraph::Errors::SearchFailedError: Query is invalid, since it contains no `search_index_definitions`."
            )
        end

        it "logs the query with error details if the query results in errors in the response" do
          query_string = <<-QUERY
            query GetColorName {
              __type {
                name
              }
            }
          QUERY

          expected_error_snippet = "'__type' is missing required arguments"

          expect {
            result = query_executor.execute(query_string, operation_name: "GetColorName")

            expect(result.dig("errors", 0, "message")).to include(expected_error_snippet)
          }.to log a_string_including("GetColorName", "resulted in errors", expected_error_snippet)
        end

        it "supports named operations and variables" do
          query = <<-QUERY
            query GetTypeName($typeName: String!) {
              __type(name: $typeName) {
                name
              }
            }

            query GetTypeFields($typeName: String!) {
              __type(name: $typeName) {
                fields {
                  name
                }
              }
            }
          QUERY

          data1 = execute_expecting_no_errors(query, operation_name: "GetTypeName", variables: {typeName: "Query"})
          expect(data1).to eq("__type" => {"name" => "Query"})

          data2 = execute_expecting_no_errors(query, operation_name: "GetTypeFields", variables: {typeName: "Color"})
          expect(data2).to eq("__type" => {"fields" => [{"name" => "blue"}, {"name" => "green"}, {"name" => "id"}, {"name" => "red"}]})
        end

        it "ignores unknown variables" do
          query = <<-QUERY
            query GetTypeName($typeName: String!) {
              __type(name: $typeName) {
                name
              }
            }
          QUERY

          data1 = execute_expecting_no_errors(query, operation_name: "GetTypeName", variables: {typeName: "Query", unknownVar: 3})
          expect(data1).to eq("__type" => {"name" => "Query"})
        end

        it "fails when variables reference undefined schema elements" do
          query = <<~QUERY
            query GetColors($colorArgs: ColorArgs) {
              colors(args: $colorArgs) {
                red
              }
            }
          QUERY

          expect {
            result = query_executor.execute(query, operation_name: "GetColors", variables: {colorArgs: {red: 3, orange: 12}})
            expect(result.dig("errors", 0, "message")).to include("$colorArgs", "ColorArgs", "orange")
          }.to log(a_string_including("resulted in errors"))
        end

        it "treats variable fields with `null` values as being unmentioned, to help static language clients avoid errors as the schema evolves" do
          query = <<~QUERY
            query GetColors($colorArgs: ColorArgs) {
              colors(args: $colorArgs) {
                red
              }
            }
          QUERY

          execute_expecting_no_errors(query, operation_name: "GetColors", variables: {colorArgs: {red: 3, orange: nil, brown: nil}})
        end

        it "does not ignore `null` values on unknown arguments in the query itself" do
          query = <<~QUERY
            query {
              colors(args: {red: 3, orange: nil, blue: nil}) {
                red
              }
            }
          QUERY

          expect {
            result = query_executor.execute(query)
            expect(result["errors"].to_s).to include("orange", "blue")
          }.to log(a_string_including("resulted in errors"))
        end

        it "calculates the `monotonic_clock_deadline` from a provided `timeout_in_ms`, and passes it along in the query context" do
          query = <<~QUERY
            query {
              __type(name: "Color") {
                name
              }
            }
          QUERY

          expect(submitted_query_context_for(query, timeout_in_ms: 500)).to include(
            monotonic_clock_deadline: monontonic_now_time + 500
          )
        end

        it "passes no `monotonic_clock_deadline` in `context` when no `timeout_in_ms` is provided" do
          query = <<~QUERY
            query {
              __type(name: "Color") {
                name
              }
            }
          QUERY

          expect(submitted_query_context_for(query)).not_to include(:monotonic_clock_deadline)
        end

        it "allows full introspection on all built-in schema types" do
          # "Touch" all the built-in types and fields; at one point, the
          # act of doing this caused a later failure when those types were
          # fetched in a GraphQL query.
          GraphQL::Schema::BUILT_IN_TYPE_NAMES.each do |type_name|
            query_executor.schema.type_named(type_name).fields_by_name.values
          end

          query = <<~QUERY
            query {
              __schema {
                types {
                  name
                  fields {
                    name
                  }
                }
              }
            }
          QUERY

          field_names_by_type_name = execute_expecting_no_errors(query)
            .fetch("__schema")
            .fetch("types")
            .each_with_object({}) do |type, hash|
              hash[type.fetch("name")] = type.fetch("fields")&.map { |f| f.fetch("name") }
            end

          expect(field_names_by_type_name).to include("__Field" => ["args", "deprecationReason", "description", "isDeprecated", "name", "type"])
        end

        it "responds reasonably when `query_string` is `nil`" do
          expect {
            result = query_executor.execute(nil)

            expect(result["errors"].to_s).to include("No query string")
          }.to log(a_string_including("resulted in errors"))
        end

        context "when extensions provide additional log data" do
          it "includes extension data in the logged duration message" do
            # Simulate an extension setting data in the query tracker
            allow(::GraphQL::Execution::Interpreter).to receive(:run_all).and_wrap_original do |original, schema, queries, context:|
              query_tracker = context[:elastic_graph_query_tracker]
              query_tracker.set_extension_data("custom_field", "custom_value")
              query_tracker.set_extension_data("another_field", "another_value")
              original.call(schema, queries, context: context)
            end

            execute_expecting_no_errors(<<-QUERY, client: Client.new(name: "client-name", source_description: "client-description"))
              query GetColors {
                colors(args: {red: 12}) {
                  red
                }
              }
            QUERY

            expect(logged_duration_message).to include(
              "custom_field" => "custom_value",
              "another_field" => "another_value"
            )
          end
        end

        context "when the schema has been customized (as in an extension like elasticgraph-apollo)" do
          before(:context) do
            multiply_resolver = Class.new do
              def initialize(elasticgraph_graphql:, config:)
              end

              def resolve(field:, object:, args:, context:)
                [
                  args.dig("operands", "x"),
                  args.dig("operands", "y"),
                  context[:additional_operand]
                ].compact.reduce(:*)
              end
            end

            ::Object.const_set(:MultiplyResolver, multiply_resolver)

            self.schema_artifacts = generate_schema_artifacts do |schema|
              schema.register_graphql_resolver :multiply, multiply_resolver, defined_at: __FILE__

              schema.on_root_query_type do |type|
                type.field "multiply", "Int" do |f|
                  f.argument("operands", "Operands!")
                  f.resolve_with :multiply
                end
              end

              schema.scalar_type "Operands" do |t|
                t.mapping type: nil
                t.json_schema type: "null"
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.index "widgets"
              end
            end
          end

          after(:context) do
            ::Object.send(:remove_const, :MultiplyResolver) # standard:disable RSpec/RemoveConst
          end

          let(:graphql) { build_graphql(schema_artifacts: schema_artifacts) }

          before do
            # stub the `require` call that happens. If we allow it to load this file it'll mess with our reported code coverage
            allow(SchemaArtifacts::RuntimeMetadata::GraphQLResolver.without_lookahead_loader).to receive(:require)
          end

          it "allows an injected resolver to resolve the custom field" do
            query = <<~EOS
              query {
                multiply(operands: {x: 3, y: 7})
              }
            EOS

            result = graphql.graphql_query_executor.execute(query)

            expect(result.to_h).to eq({"data" => {"multiply" => 21}})
          end

          it "passes custom `context` values down to the custom resolver so it can use it in its logic" do
            query = <<~EOS
              query {
                multiply(operands: {x: 3, y: 7})
              }
            EOS

            result = graphql.graphql_query_executor.execute(query, context: {additional_operand: 10})

            expect(result.to_h).to eq({"data" => {"multiply" => 210}})
          end
        end

        def define_graphql
          router = instance_double("ElasticGraph::GraphQL::DatastoreSearchRouter")
          allow(router).to receive(:msearch) do |queries, query_tracker:|
            queries.each do |query|
              allow(query).to receive(:shard_routing_values).and_return(["routing_value_1", "routing_value_2"])
            end

            query_tracker.record_datastore_queries_for_single_request(queries)

            query_tracker.record_datastore_query_metrics(
              client_duration_ms: datastore_query_client_duration_ms,
              server_duration_ms: datastore_query_server_duration_ms,
              queried_shard_count: queried_shard_count
            )

            queries.to_h { |query| [query, {}] }
          end

          build_graphql(
            schema_artifacts: schema_artifacts,
            datastore_search_router: router,
            monotonic_clock: monotonic_clock,
            slow_query_latency_warning_threshold_in_ms: slow_query_threshold_ms
          )
        end

        def define_query_executor
          define_graphql.graphql_query_executor
        end

        def submitted_query_context_for(...)
          submitted_context = nil

          allow(::GraphQL::Execution::Interpreter).to receive(:run_all).and_wrap_original do |original, schema, queries, context:|
            submitted_context = context
            original.call(schema, queries, context: context)
          end

          query_executor.execute(...)

          submitted_context
        end

        def execute_expecting_no_errors(query, query_executor: self.query_executor, **options)
          response = query_executor.execute(query, **options)
          expect(response["errors"]).to be nil
          response.fetch("data")
        end

        def logged_duration_message
          logged_jsons = logged_jsons_of_type("ElasticGraphQueryExecutorQueryDuration")
          expect(logged_jsons.size).to be < 2
          logged_jsons.first
        end

        def logged_slo_result_for(query, duration_in_ms:)
          allow(monotonic_clock).to receive(:now_in_ms).and_return(100, 100 + duration_in_ms)
          execute_expecting_no_errors(query, client: Client.new(name: "client-name", source_description: "client-description"))

          logged_duration_message.fetch("slo_result")
        end
      end
    end
  end
end
