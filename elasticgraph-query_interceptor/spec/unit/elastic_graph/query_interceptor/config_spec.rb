# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/query_interceptor/config"

module ElasticGraph
  module QueryInterceptor
    RSpec.describe Config, :in_temp_dir do
      it "returns a config instance with no interceptors if extension settings has no `query_interceptor` key" do
        config = Config.from_parsed_yaml({})

        expect(config.interceptors).to eq []
      end

      it "raises an error if configured with unknown keys" do
        expect {
          Config.from_parsed_yaml({"query_interceptor" => {"interceptors" => [], "other_key" => 3}})
        }.to raise_error Errors::ConfigError, a_string_including("other_key")
      end

      it "raises an error if configured with no `interceptors` key" do
        expect {
          Config.from_parsed_yaml({"query_interceptor" => {}})
        }.to raise_error KeyError, a_string_including("interceptors")
      end

      it "loads interceptors from disk based on config settings" do
        1.upto(3) do |i|
          ::File.write("interceptor#{i}.rb", <<~EOS)
            class Interceptor#{i}
              def initialize(elasticgraph_graphql:, config:)
              end

              def intercept(query, field:, args:, http_request:, context:)
                query
              end
            end
          EOS
        end

        config = Config.from_parsed_yaml({"query_interceptor" => {"interceptors" => [
          {"name" => "Interceptor1", "require_path" => "./interceptor1"},
          {"name" => "Interceptor2", "require_path" => "./interceptor2", "config" => {"foo" => "bar"}},
          {"name" => "Interceptor3", "require_path" => "./interceptor3"}
        ]}})

        expect(config.interceptors).to eq [
          Config::InterceptorData.new(Interceptor1, {}),
          Config::InterceptorData.new(Interceptor2, {"foo" => "bar"}),
          Config::InterceptorData.new(Interceptor3, {})
        ]
      end

      it "validates the observable interface of the interceptors, reporting an issue if they are invalid" do
        ::File.write("invalid_interceptor.rb", <<~EOS)
          class InvalidInterceptor
          end
        EOS

        expect {
          Config.from_parsed_yaml({"query_interceptor" => {"interceptors" => [
            {"name" => "InvalidInterceptor", "require_path" => "./invalid_interceptor"}
          ]}})
        }.to raise_error Errors::InvalidExtensionError, a_string_including("Missing instance methods:", "intercept")
      end
    end
  end
end
