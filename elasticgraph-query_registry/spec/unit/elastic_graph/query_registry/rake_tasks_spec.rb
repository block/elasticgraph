# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql"
require "elastic_graph/query_registry/rake_tasks"
require "fileutils"

module ElasticGraph
  module QueryRegistry
    RSpec.describe RakeTasks, :rake_task, :in_temp_dir do
      attr_reader :last_task_output
      let(:query_registry_dir) { "query_registry" }

      it "evaluates the graphql load block lazily so that if loading fails it only interferes with running tasks, not defining them" do
        # Simulate schema artifacts being out of date.
        load_graphql = lambda { raise "schema artifacts are out of date" }

        # Printing tasks is unaffected...
        output = run_rake("--tasks", &load_graphql)

        expect(output).to eq(<<~EOS)
          rake query_registry:dump_variables[client,query]  # Updates the registered information about query variables for a specific client (and optionally, a specific query)
          rake query_registry:dump_variables:all            # Updates the registered information about query variables for all clients
          rake query_registry:validate_queries              # Validates the queries registered in `query_registry`
        EOS

        # ...but when you run a task that needs the `GraphQL` instance the failure is surfaced.
        expect {
          run_rake("query_registry:validate_queries", &load_graphql)
        }.to raise_error "schema artifacts are out of date"
      end

      describe "query_registry:validate_queries" do
        it "validates each query in the subdirectory of the given dir, reporting success for each valid query" do
          register_query "client_bob", "CountWidgets.graphql", <<~EOS
            query CountWidgets {
              widgets {
                total_edge_count
              }
            }
          EOS

          register_query "client_bob", "CountComponents.graphql", <<~EOS
            query CountComponents {
              components {
                total_edge_count
              }
            }
          EOS

          register_query "client_jane", "CountParts.graphql", <<~EOS
            query CountParts {
              parts {
                total_edge_count
              }
            }
          EOS

          run_validate_task(after_dumping_variables: true)

          expect(last_task_output.string.strip).to eq(<<~EOS.strip)
            For client `client_bob`:
              - CountComponents.graphql (1 operation):
                - CountComponents: ✅
              - CountWidgets.graphql (1 operation):
                - CountWidgets: ✅

            For client `client_jane`:
              - CountParts.graphql (1 operation):
                - CountParts: ✅
          EOS
        end

        it "reports which queries are invalid" do
          register_query "client_bob", "CountWidgets.graphql", <<~EOS
            query CountWidgets {
              widgets {
                total_edge_count
              }
            }
          EOS

          register_query "client_bob", "CountComponents.graphql", <<~EOS
            query CountComponents {
              components {
                total_edge_count2
              }
              widgets(foo: 1) {
                total_edge_count
              }
            }

            query AnotherBadQuery {
              w1: foo
            }
          EOS

          register_query "client_jane", "CountParts.graphql", <<~EOS
            query CountParts
              parts {
                total_edge_count2
              }
            }
          EOS

          expect {
            run_validate_task(after_dumping_variables: true)
          }.to raise_error(a_string_including("Found 4 validation errors total across all queries."))

          expect(last_task_output.string.strip).to eq(<<~EOS.strip)
            For client `client_bob`:
              - CountComponents.graphql (2 operations):
                - CountComponents: 🛑. Got 2 validation errors:
                  1) Field 'total_edge_count2' doesn't exist on type 'ComponentConnection' (Did you mean `total_edge_count`?)
                     path: query CountComponents.components.total_edge_count2
                     source: query_registry/client_bob/CountComponents.graphql:3:5
                     code: undefinedField
                     typeName: ComponentConnection
                     fieldName: total_edge_count2

                  2) Field 'widgets' doesn't accept argument 'foo'
                     path: query CountComponents.widgets.foo
                     source: query_registry/client_bob/CountComponents.graphql:5:11
                     code: argumentNotAccepted
                     name: widgets
                     typeName: Field
                     argumentName: foo

                - AnotherBadQuery: 🛑. Got 1 validation error:
                  1) Field 'foo' doesn't exist on type 'Query'
                     path: query AnotherBadQuery.w1
                     source: query_registry/client_bob/CountComponents.graphql:11:3
                     code: undefinedField
                     typeName: Query
                     fieldName: foo

              - CountWidgets.graphql (1 operation):
                - CountWidgets: ✅

            For client `client_jane`:
              - CountParts.graphql (1 operation):
                - (no operation name): 🛑. Got 1 validation error:
                  1) Expected LCURLY, actual: IDENTIFIER ("parts") at [2, 3]
                     source: query_registry/client_jane/CountParts.graphql:2:3
          EOS
        end

        it "does not allow a single client to use the same operation name on two queries, since we want operation names to be human readable unique identifiers" do
          register_query "client_bob", "CountWidgets.graphql", <<~EOS
            query CountWidgets {
              widgets {
                total_edge_count
              }
            }
          EOS

          register_query "client_bob", "CountComponents.graphql", <<~EOS
            query CountWidgets {
              components {
                total_edge_count
              }
            }
          EOS

          expect {
            run_validate_task(after_dumping_variables: true)
          }.to raise_error(a_string_including("Found 1 validation error total across all queries."))

          expect(last_task_output.string.strip).to eq(<<~EOS.strip)
            For client `client_bob`:
              - CountComponents.graphql (1 operation):
                - CountWidgets: ✅
              - CountWidgets.graphql (1 operation):
                - CountWidgets: 🛑. Got 1 validation error:
                  1) A `CountWidgets` query already exists for `client_bob` in `CountComponents.graphql`. Each query operation must have a unique name.
          EOS
        end

        it "allows different clients to register query operations with the same name, since we don't have a global query operation namespace" do
          register_query "client_bob", "CountWidgets.graphql", <<~EOS
            query CountWidgets {
              widgets {
                total_edge_count
              }
            }
          EOS

          register_query "client_jane", "CountWidgets.graphql", <<~EOS
            query CountWidgets {
              components {
                total_edge_count
              }
            }
          EOS

          run_validate_task(after_dumping_variables: true)

          expect(last_task_output.string.strip).to eq(<<~EOS.strip)
            For client `client_bob`:
              - CountWidgets.graphql (1 operation):
                - CountWidgets: ✅

            For client `client_jane`:
              - CountWidgets.graphql (1 operation):
                - CountWidgets: ✅
          EOS
        end

        it "reports issues with variables" do
          register_query "client_bob", "CountWidgets.graphql", <<~EOS
            query CountWidgets {
              widgets {
                total_edge_count
              }
            }
          EOS

          register_query "client_jane", "CountWidgets.graphql", <<~EOS
            query CountWidgets {
              components {
                total_edge_count
              }
            }
          EOS

          expect {
            run_validate_task(after_dumping_variables: false)
          }.to raise_error(a_string_including("Found 2 validation errors total across all queries."))

          expect(last_task_output.string.strip).to eq(<<~EOS.strip)
            For client `client_bob`:
              - CountWidgets.graphql (1 operation):
                - CountWidgets: 🛑. Got 1 validation error:
                  1) No dumped variables for this operation exist. Correct by running: `rake "query_registry:dump_variables[client_bob, CountWidgets]"`


            For client `client_jane`:
              - CountWidgets.graphql (1 operation):
                - CountWidgets: 🛑. Got 1 validation error:
                  1) No dumped variables for this operation exist. Correct by running: `rake "query_registry:dump_variables[client_jane, CountWidgets]"`

          EOS
        end

        def run_validate_task(after_dumping_variables: false)
          if after_dumping_variables
            run_rake "query_registry:dump_variables:all"
          end

          run_rake "query_registry:validate_queries"
        end
      end

      describe "query_validator:dump_variables" do
        before do
          register_query "client_bob", "CountWidgets.graphql", <<~EOS
            query CountWidgets($ids: [ID!]) {
              widgets(filter: {id: {equal_to_any_of: ids}}) {
                total_edge_count
              }
            }
          EOS

          register_query "client_bob", "CountComponents.graphql", <<~EOS
            query CountComponents($ids: [ID!]) {
              components(filter: {id: {equal_to_any_of: ids}}) {
                total_edge_count
              }
            }
          EOS

          register_query "client_jane", "CountWidgets.graphql", <<~EOS
            query CountWidgets($ids: [ID!]) {
              widgets(filter: {id: {equal_to_any_of: ids}}) {
                total_edge_count
              }
            }
          EOS
        end

        describe "with client and query args" do
          it "dumps the variables for just the one query" do
            run_rake "query_registry:dump_variables[client_bob, CountWidgets]"

            expect_dumped_variables_files("client_bob/CountWidgets")
          end
        end

        describe "with just a client arg" do
          it "dumps the variables for all queries for that client" do
            run_rake "query_registry:dump_variables[client_bob]"

            expect_dumped_variables_files("client_bob/CountWidgets", "client_bob/CountComponents")
          end
        end

        describe ":all" do
          it "dumps the variables for all queries" do
            run_rake "query_registry:dump_variables:all"

            expect_dumped_variables_files(
              "client_bob/CountWidgets",
              "client_bob/CountComponents",
              "client_jane/CountWidgets"
            )
          end
        end

        def expect_dumped_variables_files(*paths)
          expected_files = paths.map { |path| "query_registry/#{path}.variables.yaml" }
          expected_output = expected_files.map { |file| "- Dumped `#{file}`." }

          expect(last_task_output.string.split("\n")).to match_array(expected_output)
          expect(Dir["**/*.variables.yaml"]).to match_array(expected_files)

          expected_files.each do |file|
            query_name = file[/Count\w+/]
            client_name = file[/client_\w+/]

            contents = ::File.read(file)
            expect(contents).to include("Generated by `rake \"query_registry:dump_variables[#{client_name}, #{query_name}]\"`.")

            dumped_vars = ::YAML.safe_load(contents)
            expect(dumped_vars).to eq(expected_dumped_content_for(query_name))
          end
        end

        def expected_dumped_content_for(query_name)
          {query_name => {"ids" => "[ID!]"}}
        end
      end

      def register_query(client_name, file_name, query_string)
        query_dir = File.join(query_registry_dir, client_name)
        FileUtils.mkdir_p(query_dir)

        full_file_name = File.join(query_dir, file_name)
        File.write(full_file_name, query_string)
      end

      def run_rake(command, &load_graphql)
        load_graphql ||= lambda { build_graphql }

        super(command) do |output|
          @last_task_output = output
          RakeTasks.new(query_registry_dir, output: output, &load_graphql)
        end
      end
    end

    # This is a separate example group because it needs `run_rake` to be defined differently from the group above.
    RSpec.describe RakeTasks, ".from_yaml_file", :rake_task do
      let(:query_registry_dir) { "query_registry" }

      it "loads the graphql instance from the given yaml file" do
        output = run_rake "--tasks"

        expect(output).to include("rake query_registry:validate_queries")
      end

      def run_rake(*args)
        Dir.chdir CommonSpecHelpers::REPO_ROOT do
          super(*args) do |output|
            RakeTasks.from_yaml_file(CommonSpecHelpers.test_settings_file, query_registry_dir, output: output).tap do |tasks|
              expect(tasks.send(:graphql)).to be_a(GraphQL)
            end
          end
        end
      end
    end
  end
end
