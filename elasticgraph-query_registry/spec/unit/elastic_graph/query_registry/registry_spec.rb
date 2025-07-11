# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql"
require "elastic_graph/graphql/client"
require "elastic_graph/query_registry/registry"
require "logger"
require "stringio"

module ElasticGraph
  module QueryRegistry
    RSpec.describe Registry do
      let(:schema) { build_graphql.schema }

      let(:widget_name_string) do
        <<~EOS.strip
          query WidgetName {
            __type(name: "Widget") {
              name
            }
          }
        EOS
      end

      let(:part_name_string) do
        <<~EOS.strip
          query PartName {
            __type(name: "Part") {
              name
            }
          }
        EOS
      end

      describe "#build_and_validate_query" do
        shared_examples_for "any case when a query is returned" do
          it "allows the returned query to be executed multiple times with different variables" do
            # This query uses a fragment to ensure that our query canonicalization logic (which looks at
            # query.document.definitions) can handle multiple kinds of definitions (operations and fragments).
            any_name_query = <<~EOS
              query GetTypeName($name: String!) {
                __type(name: $name) {
                  ...typeFields
                }
              }

              fragment typeFields on __Type {
                name
              }
            EOS

            registry = prepare_registry_with(any_name_query)

            result = execute_allowed_query(registry, any_name_query, variables: {"name" => "Address"})
            expect(result.to_h).to eq(result_with_type_name("Address"))

            result = execute_allowed_query(registry, any_name_query, variables: {"name" => "Component"})
            expect(result.to_h).to eq(result_with_type_name("Component"))

            result = execute_allowed_query(registry, any_name_query, variables: {"name" => "Address"})
            expect(result.to_h).to eq(result_with_type_name("Address"))
          end

          it "allows the returned query to be executed multiple times with different operations" do
            widget_or_part_name_query = <<~EOS
              #{widget_name_string}

              #{part_name_string}
            EOS

            registry = prepare_registry_with(widget_or_part_name_query)

            result = execute_allowed_query(registry, widget_or_part_name_query, operation_name: "WidgetName")
            expect(result.to_h).to eq(result_with_type_name("Widget"))

            result = execute_allowed_query(registry, widget_or_part_name_query, operation_name: "PartName")
            expect(result.to_h).to eq(result_with_type_name("Part"))

            result = execute_allowed_query(registry, widget_or_part_name_query, operation_name: "WidgetName")
            expect(result.to_h).to eq(result_with_type_name("Widget"))
          end
        end

        context "for a named client who has registered queries" do
          context "when given a query string that is byte-for-byte the same as a registered query" do
            include_examples "any case when a query is returned"

            def prepare_registry_with(query_string)
              registry_with({"my_client" => [query_string]})
            end

            def execute_allowed_query(registry, query_string, **options)
              super(registry, query_string, client: client_named("my_client"), **options)
            end
          end

          context "when given a query string that lacks the `@egLatencySlo` directive the registered query has" do
            include_examples "any case when a query is returned"

            def prepare_registry_with(query_string)
              query_string = add_query_directives_to(query_string, "@eg_latency_slo(ms: 2000)")
              registry_with({"my_client" => [query_string]})
            end

            def execute_allowed_query(registry, query_string, **options)
              super(registry, query_string, client: client_named("my_client"), **options)
            end
          end

          context "when given a query string that has a `@egLatencySlo` directive the registered query lacks" do
            include_examples "any case when a query is returned"

            def prepare_registry_with(query_string)
              registry_with({"my_client" => [query_string]})
            end

            def execute_allowed_query(registry, query_string, **options)
              query_string = add_query_directives_to(query_string, "@eg_latency_slo(ms: 2000)")
              super(registry, query_string, client: client_named("my_client"), **options)
            end
          end

          context "when given a query string that has a different `@egLatencySlo` directive value compared to the registered query" do
            include_examples "any case when a query is returned"

            def prepare_registry_with(query_string)
              query_string = add_query_directives_to(query_string, "@eg_latency_slo(ms: 4000)")
              registry_with({"my_client" => [query_string]})
            end

            def execute_allowed_query(registry, query_string, **options)
              query_string = add_query_directives_to(query_string, "@eg_latency_slo(ms: 2000)")
              super(registry, query_string, client: client_named("my_client"), **options)
            end
          end

          context "when given a query string that has an extra directive (that is not `@egLatencySlo`) not on the registered query" do
            it "returns a validation error since the extra directive could be a substantive difference" do
              registry = registry_with({"my_client" => [widget_name_string, part_name_string]})
              modified_parts_query = add_query_directives_to(part_name_string, "@some_other_directive")

              query, errors = registry.build_and_validate_query(modified_parts_query, client: client_named("my_client"))

              expect(errors).to contain_exactly(a_string_including(
                "Query PartName", "differs from the registered form of `PartName`", "my_client"
              ))
              expect(query.query_string).to eq(modified_parts_query)
            end
          end

          context "when given a query string that has lacks a directive (that is not `@egLatencySlo`) present on the registered query" do
            it "returns a validation error since the extra directive could be a substantive difference" do
              registry = registry_with({"my_client" => [widget_name_string, add_query_directives_to(part_name_string, "@some_other_directive")]})

              query, errors = registry.build_and_validate_query(part_name_string, client: client_named("my_client"))

              expect(errors).to contain_exactly(a_string_including(
                "Query PartName", "differs from the registered form of `PartName`", "my_client"
              ))
              expect(query.query_string).to eq(part_name_string)
            end
          end

          context "when the client is also in `allow_any_query_for_clients`" do
            context "for a query that is unregistered" do
              include_examples "any case when a query is returned"

              def prepare_registry_with(query_string)
                some_other_query = <<~EOS
                  query SomeOtherRegisteredQuery {
                    __typename
                  }
                EOS

                registry_with({"my_client" => [some_other_query]}, allow_any_query_for_clients: ["my_client"])
              end

              def execute_allowed_query(registry, query_string, **options)
                super(registry, query_string, client: client_named("my_client"), **options)
              end
            end

            context "for a query that is identical to a registered one" do
              include_examples "any case when a query is returned"

              def prepare_registry_with(query_string)
                registry_with({"my_client" => [query_string]}, allow_any_query_for_clients: ["my_client"])
              end

              def execute_allowed_query(registry, query_string, **options)
                super(registry, query_string, client: client_named("my_client"), **options)
              end
            end

            context "for a query that has the same name as a registered one but differs substantially" do
              it "executes it even though it differs from the registered query since the client is in `allow_any_query_for_clients`" do
                query1 = "query SomeQuery { __typename }"
                query2 = "query SomeQuery { t: __typename }"

                registry = registry_with({"my_client" => [query1]}, allow_any_query_for_clients: ["my_client"])

                expect(execute_allowed_query(registry, query2, client: client_named("my_client")).to_h).to eq({"data" => {"t" => "Query"}})
              end
            end

            context "when the client is also in `warn_on_unregistered_query_for_clients`" do
              it "logs warnings even though the client is in allow list" do
                logger = Logger.new(StringIO.new)
                allow(logger).to receive(:warn)

                query1 = "query SomeQuery { __typename }"
                query2 = "query SomeQuery { t: __typename }"

                registry = Registry.new(
                  schema,
                  client_names: ["my_client"],
                  allow_unregistered_clients: false,
                  allow_any_query_for_clients: ["my_client"],
                  warn_on_unregistered_query_for_clients: ["my_client"],
                  logger: logger
                ) { |client_name| [query1] }

                query, errors = registry.build_and_validate_query(query2, client: client_named("my_client"))

                expect(errors).to be_empty
                expect(query.query_string).to eq(query2)
                # Should log warning even though client is in allow list
                expect(logger).to have_received(:warn).with(a_string_including("Query registry warning"))
              end
            end
          end

          context "when `allow_unregistered_clients` is `true`" do
            it "still validates that the given queries match what has been registered for this client" do
              query1 = <<~QUERY
                query SomeQuery {
                  __typename
                }
              QUERY

              query2 = "query SomeQuery { t: __typename }"
              query3 = "query SomeQuery3 { t: __typename }"

              registry = registry_with({"my_client" => [query1]}, allow_unregistered_clients: true)

              expect(execute_allowed_query(registry, query1, client: client_named("my_client")).to_h).to eq({"data" => {"__typename" => "Query"}})

              query, errors = registry.build_and_validate_query(query2, client: client_named("my_client"))
              expect(errors).to contain_exactly(a_string_including(
                "Query SomeQuery", "differs from the registered form of `SomeQuery`", "my_client"
              ))
              expect(query.query_string).to eq(query2)

              query, errors = registry.build_and_validate_query(query3, client: client_named("my_client"))
              expect(errors).to contain_exactly(a_string_including(
                "Query SomeQuery3", "is unregistered", "my_client"
              ))
              expect(query.query_string).to eq(query3)
            end
          end

          def add_query_directives_to(query_string, query_directives_string)
            # https://rubular.com/r/T2UXnaXfWr8nIg has examples of this regex
            query_string.gsub(/^query (\w+)(?:\([^)]+\))?/) { |it| "#{it} #{query_directives_string}" }
          end

          context "when given a query string that has only minor formatting differences compared to a registered query" do
            include_examples "any case when a query is returned"

            it "caches the parsed form of the mostly recently seen alternate query string, to avoid unneeded reparsing" do
              parse_counts_by_query_string = track_parse_counts

              registry = prepare_registry_with(part_name_string)
              get_allowed_query(registry, part_name_string, client: client_named("my_client"))

              expect(parse_counts_by_query_string).to eq(part_name_string => 1)

              modified_query_string1 = modify_query_string(part_name_string)
              get_allowed_query(registry, modified_query_string1, client: client_named("my_client"))
              expect(parse_counts_by_query_string).to eq(part_name_string => 1, modified_query_string1 => 1)

              # Now that `modified_query_string1` is cached, further requests with that query string should not
              # need to be re-parsed.
              3.times do
                get_allowed_query(registry, modified_query_string1, client: client_named("my_client"))
              end
              expect(parse_counts_by_query_string).to eq(part_name_string => 1, modified_query_string1 => 1)

              modified_query_string2 = modify_query_string(modified_query_string1)
              get_allowed_query(registry, modified_query_string2, client: client_named("my_client"))
              expect(parse_counts_by_query_string).to eq(
                part_name_string => 1,
                modified_query_string1 => 1,
                modified_query_string2 => 1
              )

              # ...but now that the client submitted a different form of the query, the prior form should have
              # been evicted from the cache, and we expect the older form to be need to be re-parsed.
              get_allowed_query(registry, modified_query_string1, client: client_named("my_client"))
              expect(parse_counts_by_query_string).to eq(
                part_name_string => 1,
                modified_query_string1 => 2,
                modified_query_string2 => 1
              )

              # ...but so long as `modified_query_string1` keeps getting re-used, no further re-parsings should be required.
              3.times do
                get_allowed_query(registry, modified_query_string1, client: client_named("my_client"))
              end
              expect(parse_counts_by_query_string).to eq(
                part_name_string => 1,
                modified_query_string1 => 2,
                modified_query_string2 => 1
              )
            end

            def prepare_registry_with(query_string)
              registry_with({"my_client" => [query_string]})
            end

            def execute_allowed_query(registry, query_string, **options)
              modified_query_string = modify_query_string(query_string)
              returned_query = get_allowed_query(registry, modified_query_string, client: client_named("my_client"), **options)
              returned_query.result
            end

            def modify_query_string(query_string)
              "# This is a leading comment\n#{query_string}"
            end
          end

          it "returns a validation error for a query string that has substantive differences compared to a registered query" do
            registry = registry_with({"my_client" => [widget_name_string, part_name_string]})
            modified_parts_query = part_name_string.sub("name\n", "the_name: name\n")

            query, errors = registry.build_and_validate_query(modified_parts_query, client: client_named("my_client"))

            expect(errors).to contain_exactly(a_string_including(
              "Query PartName", "differs from the registered form of `PartName`", "my_client"
            ))
            expect(query.query_string).to eq(modified_parts_query)
          end

          it "returns a validation error for an unregistered invalid query" do
            registry = registry_with({"my_client" => [widget_name_string, part_name_string]})

            query, errors = registry.build_and_validate_query("not_a_query", client: client_named("my_client"))

            expect(errors).to contain_exactly(a_string_including(
              "Query anonymous", "is unregistered", "my_client",
              "no registered query with a `` operation"
            ))
            expect(query.query_string).to eq("not_a_query")
          end

          it "echoes no validation errors for a registered invalid query when it is byte-for-byte the same" do
            registry = registry_with({"my_client" => ["not_a_query"]})

            query, errors = registry.build_and_validate_query("not_a_query", client: client_named("my_client"))

            expect(errors).to be_empty
            expect(query.result["errors"].to_s).to include('IDENTIFIER (\"not_a_query\")')
          end

          it "does not consider a query registered by a different client" do
            registry = registry_with({"client1" => [widget_name_string], "client2" => [part_name_string]})

            query, errors = registry.build_and_validate_query(part_name_string, client: client_named("client1"))
            expect(errors).to contain_exactly(a_string_including(
              "Query PartName", "is unregistered", "client1",
              "no registered query with a `PartName` operation"
            ))
            expect(query.query_string).to eq(part_name_string)

            query, errors = registry.build_and_validate_query(part_name_string, client: client_named("client2"))
            expect(errors).to be_empty
            expect(query.query_string).to eq(part_name_string)
          end

          it "avoids re-parsing the query string when the query string is byte-for-byte identical to a registered one, for efficiency" do
            parse_counts_by_query_string = track_parse_counts
            registry = registry_with({"client1" => [widget_name_string, part_name_string]})

            3.times do
              result = execute_allowed_query(registry, widget_name_string, client: client_named("client1"))
              expect(result.to_h).to eq(result_with_type_name("Widget"))

              result = execute_allowed_query(registry, part_name_string, client: client_named("client1"))
              expect(result.to_h).to eq(result_with_type_name("Part"))
            end

            expect(parse_counts_by_query_string).to eq(
              widget_name_string => 1,
              part_name_string => 1
            )
          end
        end

        it "always allows the internal ElasticGraph client to submit the eager load query that happens at boot time" do
          registry = registry_with({}, allow_unregistered_clients: false, allow_any_query_for_clients: [])

          result = execute_allowed_query(registry, GraphQL::EAGER_LOAD_QUERY, client: GraphQL::Client::ELASTICGRAPH_INTERNAL)

          expect(result.to_h.dig("data", "__schema", "types")).to include({"kind" => "OBJECT"})
        end

        shared_examples_for "a client not in the registry" do
          context "when `allow_unregistered_clients` is `false`" do
            it "returns validation errors when given a valid query" do
              registry = registry_with({"my_client" => [widget_name_string, part_name_string]}, allow_unregistered_clients: false)

              query, errors = registry.build_and_validate_query(part_name_string, client: client)

              expect(errors).to contain_exactly(a_string_including("not a registered client", client&.name.to_s))
              expect(query.query_string).to eq(part_name_string)
            end

            it "returns validation errors when given an invalid query" do
              registry = registry_with({"my_client" => [widget_name_string, part_name_string]}, allow_unregistered_clients: false)

              query, errors = registry.build_and_validate_query("not_a_query", client: client)

              expect(errors).to contain_exactly(a_string_including("not a registered client", client&.name.to_s))
              expect(query.query_string).to eq("not_a_query")
            end
          end

          context "when `allow_unregistered_clients` is `true`" do
            include_examples "any case when a query is returned"

            it "returns no validation errors for an invalid query" do
              registry = registry_with({}, allow_unregistered_clients: true)

              query, errors = registry.build_and_validate_query("not_a_query", client: client)

              expect(errors).to be_empty
              expect(query.result["errors"].to_s).to include('IDENTIFIER (\"not_a_query\")')
            end

            def prepare_registry_with(query_string)
              registry_with({"some_client_these_tests_dont_use" => [query_string]}, allow_unregistered_clients: true)
            end

            def execute_allowed_query(registry, query_string, **options)
              super(registry, query_string, client: client, **options)
            end
          end
        end

        context "for a named client who has no registered queries" do
          include_examples "a client not in the registry"
          let(:client) { client_named("unregistered_client") }

          context "when the client is in `allow_any_query_for_clients`" do
            include_examples "any case when a query is returned"

            def prepare_registry_with(query_string)
              registry_with({}, allow_unregistered_clients: false, allow_any_query_for_clients: [client.name])
            end

            def execute_allowed_query(registry, query_string, **options)
              super(registry, query_string, client: client, **options)
            end
          end

          context "when the client is in `warn_on_unregistered_query_for_clients`" do
            it "allows the query to execute and logs a warning" do
              logger = Logger.new(StringIO.new)
              allow(logger).to receive(:warn)

              registry = Registry.new(
                schema,
                client_names: [client.name], # Include the client in the registered clients list
                allow_unregistered_clients: false,
                allow_any_query_for_clients: [],
                warn_on_unregistered_query_for_clients: [client.name],
                logger: logger
              ) { |client_name| [] } # But provide no registered queries for this client

              query, errors = registry.build_and_validate_query(widget_name_string, client: client)

              expect(errors).to be_empty
              expect(query.query_string).to eq(widget_name_string)
              expect(logger).to have_received(:warn).with(a_string_including("Query registry warning"))
            end
          end
        end

        context "for a client with no `name`" do
          include_examples "a client not in the registry"
          let(:client) { client_named(nil) }
        end

        context "for a nil client" do
          include_examples "a client not in the registry"
          let(:client) { nil }
        end

        it "defers parsing queries for a client until the client submits its first query, so that low QPS clients with many large queries are ignored until needed" do
          parse_counts_by_query_string = track_parse_counts

          registry = registry_with({"client1" => [widget_name_string], "client2" => [part_name_string]})

          3.times do
            query = get_allowed_query(registry, widget_name_string, client: client_named("client1"))
            expect(query.query_string).to eq(widget_name_string)
          end

          expect(parse_counts_by_query_string).to eq(widget_name_string => 1)

          3.times do
            query = get_allowed_query(registry, part_name_string, client: client_named("client2"))
            expect(query.query_string).to eq(part_name_string)
          end

          expect(parse_counts_by_query_string).to eq(widget_name_string => 1, part_name_string => 1)
        end

        def registry_with(queries_by_client_name, allow_unregistered_clients: false, allow_any_query_for_clients: [], warn_on_unregistered_query_for_clients: [])
          Registry.new(
            schema,
            client_names: queries_by_client_name.keys,
            allow_unregistered_clients: allow_unregistered_clients,
            allow_any_query_for_clients: allow_any_query_for_clients,
            warn_on_unregistered_query_for_clients: warn_on_unregistered_query_for_clients,
            logger: Logger.new(StringIO.new) # Use a dummy logger for tests
          ) do |client_name|
            # We use `fetch` here to demonstrate that the registry does not call our block
            # with any client names outside of the passed list.
            queries_by_client_name.fetch(client_name)
          end
        end

        def get_allowed_query(registry, query_string, **options)
          query, errors = registry.build_and_validate_query(query_string, **options)
          expect(errors).to be_empty
          query
        end

        def execute_allowed_query(registry, query_string, **options)
          get_allowed_query(registry, query_string, **options).tap do |query|
            # Verify that the executed query is exactly what was submitted rather than what was registered.
            # This particularly matters with the `@egLatencySlo` directive. We want the value on the query
            # to be used when it differs from the SLO threshold on the registered query.
            expect(query.query_string.strip).to eq(query_string.strip)
          end.result
        end

        def result_with_type_name(name)
          {"data" => {"__type" => {"name" => name}}}
        end

        def track_parse_counts
          parse_counts_by_query_string = ::Hash.new(0)

          allow(::GraphQL).to receive(:parse).and_wrap_original do |original, query_string, **options|
            parse_counts_by_query_string[query_string] += 1 unless query_string == GraphQL::EAGER_LOAD_QUERY
            original.call(query_string, **options)
          end

          parse_counts_by_query_string
        end
      end

      describe ".build_from_directory", :in_temp_dir do
        let(:query_registry_dir) { "registered_queries" }
        let(:registry) do
          Registry.build_from_directory(
            schema,
            query_registry_dir,
            allow_unregistered_clients: false,
            allow_any_query_for_clients: [],
            warn_on_unregistered_query_for_clients: [],
            logger: Logger.new(StringIO.new) # Use a dummy logger for tests
          )
        end

        it "builds an instance based on the queries in the given directory" do
          register_query("client1", "WidgetName.graphql", widget_name_string)

          query, errors = registry.build_and_validate_query(widget_name_string, client: client_named("client1"))
          expect(errors).to be_empty
          expect(query.query_string).to eq(widget_name_string)

          query, errors = registry.build_and_validate_query(part_name_string, client: client_named("client1"))
          expect(errors).to contain_exactly(a_string_including(
            "Query PartName", "is unregistered", "client1",
            "no registered query with a `PartName` operation"
          ))
          expect(query.query_string).to eq(part_name_string)

          query, errors = registry.build_and_validate_query(widget_name_string, client: client_named("other-client"))
          expect(errors).to contain_exactly(a_string_including("not a registered client", "other-client"))
          expect(query.query_string).to eq(widget_name_string)
        end

        it "defers reading from disk until it needs to, and caches the disk results after that" do
          file_reads_by_name = track_file_reads

          register_query("client1", "WidgetName.graphql", widget_name_string)
          register_query("client2", "WidgetName.graphql", part_name_string)
          register_query("client2", "PartName.graphql", part_name_string)

          expect(file_reads_by_name).to be_empty

          registry.build_and_validate_query(widget_name_string, client: client_named("client1"))
          expect(file_reads_by_name).to eq({
            "registered_queries/client1/WidgetName.graphql" => 1
          })

          registry.build_and_validate_query(widget_name_string, client: client_named("client2"))
          expect(file_reads_by_name).to eq({
            "registered_queries/client1/WidgetName.graphql" => 1,
            "registered_queries/client2/WidgetName.graphql" => 1,
            "registered_queries/client2/PartName.graphql" => 1
          })

          # further uses of the registry should trigger no more reads.
          expect {
            registry.build_and_validate_query(widget_name_string, client: client_named("client1"))
            registry.build_and_validate_query(part_name_string, client: client_named("client1"))
            registry.build_and_validate_query(widget_name_string, client: client_named("client2"))
            registry.build_and_validate_query(part_name_string, client: client_named("client2"))
          }.not_to change { file_reads_by_name }
        end

        it "ignores client directory files that do not end in `.graphql`" do
          file_reads_by_name = track_file_reads

          register_query("client1", "WidgetName.graphql", widget_name_string)
          register_query("client1", "README.md", "## Not a GraphQL query")

          query, errors = registry.build_and_validate_query(widget_name_string, client: client_named("client1"))
          expect(errors).to be_empty
          expect(query.query_string).to eq(widget_name_string)

          expect(file_reads_by_name.keys).to contain_exactly(
            "registered_queries/client1/WidgetName.graphql"
          )
        end

        def register_query(client_name, file_name, query_string)
          query_dir = File.join(query_registry_dir, client_name)
          FileUtils.mkdir_p(query_dir)

          full_file_name = File.join(query_dir, file_name)
          File.write(full_file_name, query_string)
        end

        def track_file_reads
          file_reads_by_name = ::Hash.new(0)

          allow(::File).to receive(:read).and_wrap_original do |original, file_name|
            # :nocov: -- the `else` branch here is only covered when the test is run in isolation
            # (in that case, there are a bunch of config files that are read off disk).
            # When run in a larger test suite those config files have already been read
            # and cached in memory.
            file_reads_by_name[file_name] += 1 if file_name.include?(query_registry_dir)
            # :nocov:
            original.call(file_name)
          end

          file_reads_by_name
        end
      end

      def client_named(name)
        GraphQL::Client.new(name: name, source_description: "some-description")
      end
    end
  end
end
