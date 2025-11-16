# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/elasticsearch/client"
require "elastic_graph/graphql/client"
require "elastic_graph/query_registry/graphql_extension"
require "elastic_graph/support/hash_util"
require "fileutils"
require "graphql"
require "yaml"

module ElasticGraph
  RSpec.describe "QueryRegistry", :capture_logs, :in_temp_dir do
    let(:query_registry_dir) { "query_registry" }

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

    it "responds to unregistered queries with a clear error while allowing registered queries" do
      register_query "client1", "WidgetName", widget_name_string
      register_query "client2", "PartName", part_name_string

      query_executor = build_query_executor_with_registry_options(
        allow_unregistered_clients: false,
        allow_any_query_for_clients: ["adhoc_client"],
        path_to_registry: query_registry_dir
      )

      expect(execute(query_executor, widget_name_string, on_behalf_of: "client1")).to eq("data" => {"__type" => {"name" => "Widget"}})
      expect(execute(query_executor, part_name_string, on_behalf_of: "client2")).to eq("data" => {"__type" => {"name" => "Part"}})
      expect(execute(query_executor, part_name_string, on_behalf_of: "adhoc_client")).to eq("data" => {"__type" => {"name" => "Part"}})

      expect {
        expect(execute(query_executor, widget_name_string, on_behalf_of: "client2")).to match("errors" => [
          {"message" => a_string_including("Query WidgetName", "is unregistered", "client2")}
        ])
        expect(execute(query_executor, part_name_string, on_behalf_of: "client1")).to match("errors" => [
          {"message" => a_string_including("Query PartName", "is unregistered", "client1")}
        ])
        expect(execute(query_executor, part_name_string, on_behalf_of: "client3")).to match("errors" => [
          {"message" => a_string_including("client3", "is not a registered client")}
        ])
      }.to log_warning a_string_including("is unregistered")
    end

    it "allows the ElasticGraph eager-loading query to proceed even with restrictive options" do
      register_query "client1", "WidgetName", widget_name_string

      graphql = build_graphql_with_registry_options(
        allow_unregistered_clients: false,
        allow_any_query_for_clients: [],
        path_to_registry: query_registry_dir
      )

      executed_query_strings = track_executed_query_strings
      graphql.load_dependencies_eagerly
      expect(executed_query_strings).to eq [GraphQL::EAGER_LOAD_QUERY]
    end

    it "does nothing when loaded but not configured" do
      query_executor = build_query_executor_with_registry_options

      expect(execute(query_executor, widget_name_string, on_behalf_of: "client1")).to eq("data" => {"__type" => {"name" => "Widget"}})
      expect(execute(query_executor, widget_name_string, on_behalf_of: "client2")).to eq("data" => {"__type" => {"name" => "Widget"}})
      expect(execute(query_executor, part_name_string, on_behalf_of: "client2")).to eq("data" => {"__type" => {"name" => "Part"}})
      expect(execute(query_executor, part_name_string, on_behalf_of: "adhoc_client")).to eq("data" => {"__type" => {"name" => "Part"}})
    end

    it "handles a request that has no query" do
      register_query "client1", "WidgetName", widget_name_string

      query_executor = build_query_executor_with_registry_options(
        allow_unregistered_clients: false,
        allow_any_query_for_clients: [],
        path_to_registry: query_registry_dir
      )

      expect {
        expect(execute(query_executor, nil, on_behalf_of: "client1")).to match("errors" => [
          {"message" => a_string_including("Query (no query string) is unregistered", "client1")}
        ])
      }.to log_warning a_string_including("is unregistered")
    end

    it "logs query_registered=true when a query is registered for the client" do
      register_query "client1", "WidgetName", widget_name_string

      query_executor = build_query_executor_with_registry_options(
        allow_unregistered_clients: false,
        allow_any_query_for_clients: [],
        path_to_registry: query_registry_dir
      )

      expect {
        execute(query_executor, widget_name_string, on_behalf_of: "client1")
      }.to log a_string_including('"query_registered": "true"')
    end

    it "logs query_registered=false when a query is not registered for the client" do
      register_query "client1", "WidgetName", widget_name_string

      query_executor = build_query_executor_with_registry_options(
        allow_unregistered_clients: false,
        allow_any_query_for_clients: [],
        path_to_registry: query_registry_dir
      )

      expect {
        execute(query_executor, part_name_string, on_behalf_of: "client1")
      }.to log a_string_including('"query_registered": "false"')
    end

    it "logs query_registered=false for unregistered clients" do
      register_query "client1", "WidgetName", widget_name_string

      query_executor = build_query_executor_with_registry_options(
        allow_unregistered_clients: true,
        allow_any_query_for_clients: [],
        path_to_registry: query_registry_dir
      )

      expect {
        execute(query_executor, widget_name_string, on_behalf_of: "unregistered_client")
      }.to log a_string_including('"query_registered": "false"')
    end

    it "logs query_registered=true when a client in allow_any_query_for_clients uses a registered query" do
      register_query "adhoc_client", "WidgetName", widget_name_string

      query_executor = build_query_executor_with_registry_options(
        allow_unregistered_clients: false,
        allow_any_query_for_clients: ["adhoc_client"],
        path_to_registry: query_registry_dir
      )

      expect {
        execute(query_executor, widget_name_string, on_behalf_of: "adhoc_client")
      }.to log a_string_including('"query_registered": "true"')
    end

    it "logs query_registered=false when a client in allow_any_query_for_clients uses an unregistered query" do
      register_query "adhoc_client", "WidgetName", widget_name_string

      query_executor = build_query_executor_with_registry_options(
        allow_unregistered_clients: false,
        allow_any_query_for_clients: ["adhoc_client"],
        path_to_registry: query_registry_dir
      )

      expect {
        execute(query_executor, part_name_string, on_behalf_of: "adhoc_client")
      }.to log a_string_including('"query_registered": "false"')
    end

    it "logs query_registered=true when a query differs only in whitespace or comments from a registered query" do
      register_query "client1", "WidgetName", widget_name_string

      query_executor = build_query_executor_with_registry_options(
        allow_unregistered_clients: false,
        allow_any_query_for_clients: [],
        path_to_registry: query_registry_dir
      )

      # Add extra whitespace and a comment
      modified_query = <<~EOS.strip
        # This is a comment
        query WidgetName {
          __type(name:    "Widget") {
            name
          }
        }
      EOS

      expect {
        execute(query_executor, modified_query, on_behalf_of: "client1")
      }.to log a_string_including('"query_registered": "true"')
    end

    def build_query_executor_with_registry_options(**options)
      build_graphql_with_registry_options(**options).graphql_query_executor
    end

    def build_graphql_with_registry_options(**options)
      extension_settings =
        if options.empty?
          {}
        else
          {"query_registry" => Support::HashUtil.stringify_keys(options)}
        end

      build_graphql(
        extension_settings: extension_settings,
        extension_modules: [QueryRegistry::GraphQLExtension],
        client_faraday_adapter: DatastoreCore::Configuration::ClientFaradayAdapter.new(
          name: :test,
          require: nil
        )
      )
    end

    def execute(query_executor, query_string, on_behalf_of:)
      query_executor.execute(query_string, client: GraphQL::Client.new(name: on_behalf_of, source_description: "some-description")).to_h
    end

    def register_query(client_name, query_name, query_string)
      query_dir = File.join(query_registry_dir, client_name)
      FileUtils.mkdir_p(query_dir)

      full_file_name = File.join(query_dir, query_name) + ".graphql"
      File.write(full_file_name, query_string)
    end

    def track_executed_query_strings
      executed_query_strings = []

      allow(::GraphQL::Execution::Interpreter).to receive(:run_all).and_wrap_original do |original, schema, queries, **options|
        executed_query_strings.concat(queries.map(&:query_string))
        original.call(schema, queries, **options)
      end

      executed_query_strings
    end
  end
end
