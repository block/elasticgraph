# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/rack/graphql_endpoint"
require "open3"
require "rack/builder"
require "rack/static"
require "shellwords"
require "tmpdir"

module ElasticGraph
  # A [Rack](https://github.com/rack/rack) application that serves both an ElasticGraph GraphQL endpoint
  # and a [GraphiQL IDE](https://github.com/graphql/graphiql). This can be used for local development,
  # mounted in a [Rails](https://rubyonrails.org/) application, or run in any other Rack-compatible context.
  #
  # @example Simple config.ru to serve an ElasticGraph GraphiQL IDE
  #   require "elastic_graph/graphql"
  #   require "elastic_graph/graphiql"
  #
  #   graphql = ElasticGraph::GraphQL.from_yaml_file("config/settings/development.yaml")
  #   run ElasticGraph::GraphiQL.new(graphql)
  module GraphiQL
    # Builds a [Rack](https://github.com/rack/rack) application that serves both an ElasticGraph GraphQL endpoint
    # and a [GraphiQL IDE](https://github.com/graphql/graphiql).
    #
    # @param graphql [ElasticGraph::GraphQL] ElasticGraph GraphQL instance
    # @return [Rack::Builder] built Rack application
    def self.new(graphql, output: $stdout)
      tarball_path = ::File.join(__dir__.to_s, "graphiql/assets.tar.gz")
      static_content_root = ::Dir.mktmpdir("elasticgraph_graphiql")
      output.puts "Extracting GraphiQL assets from #{tarball_path} to #{static_content_root}..."

      tar_command = "tar -xzf #{::Shellwords.escape(tarball_path)} -C #{::Shellwords.escape(static_content_root)}"
      tar_output, status = ::Open3.capture2e(tar_command)

      unless status.success?
        error_message = "Failed to extract GraphiQL assets from #{tarball_path}.\n"
        error_message += "Command: '#{tar_command}'\n"
        error_message += "Exit Status: #{status.exitstatus}\n"
        error_message += "Output: #{tar_output}"

        raise error_message
      end

      output.puts "GraphiQL assets extracted successfully to #{static_content_root}."
      graphql_endpoint = Rack::GraphQLEndpoint.new(graphql)

      ::Rack::Builder.new do
        # @type self: ::Rack::Builder
        use ::Rack::Static, urls: ["/assets", "/favicon.svg", "/monacoeditorwork"], root: static_content_root
        use ::Rack::Static, urls: {"/" => "index.html"}, root: static_content_root

        map "/graphql" do
          run graphql_endpoint
        end
      end
    end
  end
end
