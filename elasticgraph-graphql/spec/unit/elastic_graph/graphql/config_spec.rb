# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/config"
require "yaml"

module ElasticGraph
  class GraphQL
    RSpec.describe Config do
      it "sets config values from the given parsed YAML" do
        config = Config.from_parsed_yaml("graphql" => {
          "default_page_size" => 27,
          "max_page_size" => 270,
          "slow_query_latency_warning_threshold_in_ms" => 3200,
          "extension_modules" => [],
          "client_resolver" => {
            "extension_name" => "ElasticGraph::GraphQL::ClientResolvers::ViaHTTPHeader",
            "require_path" => "support/client_resolvers",
            "header_name" => "X-Client-Name"
          }
        })

        expect(config.default_page_size).to eq 27
        expect(config.max_page_size).to eq 270
        expect(config.slow_query_latency_warning_threshold_in_ms).to eq 3200
        expect(config.extension_modules).to eq []
        expect(config.client_resolver).to eq ClientResolvers::ViaHTTPHeader.new({"header_name" => "X-Client-Name"})
      end

      it "provides reasonable defaults for some optional settings" do
        config = Config.from_parsed_yaml("graphql" => {
          "default_page_size" => 27,
          "max_page_size" => 270
        })

        expect(config.default_page_size).to eq 27
        expect(config.max_page_size).to eq 270
        expect(config.slow_query_latency_warning_threshold_in_ms).to eq 5000
        expect(config.extension_modules).to eq []
        expect(config.client_resolver).to be_a Client::DefaultResolver
      end

      it "raises an error when given an unrecognized config setting" do
        expect {
          Config.from_parsed_yaml("graphql" => {
            "default_page_size" => 27,
            "max_page_size" => 270,
            "fake_setting" => 23
          })
        }.to raise_error Errors::ConfigError, a_string_including("fake_setting")
      end

      describe "#client_resolver" do
        it "raises an error when given an invalid require path" do
          expect {
            Config.from_parsed_yaml("graphql" => {
              "default_page_size" => 27,
              "max_page_size" => 270,
              "client_resolver" => {
                "extension_name" => "ElasticGraph::GraphQL::ClientResolvers::ViaHTTPHeader",
                "require_path" => "support/client_resolvers_typo",
                "header_name" => "X-CLIENT-NAME"
              }
            })
          }.to raise_error LoadError, a_string_including("support/client_resolvers_typo")
        end

        it "raises an error when given an invalid name" do
          expect {
            Config.from_parsed_yaml("graphql" => {
              "default_page_size" => 27,
              "max_page_size" => 270,
              "client_resolver" => {
                "extension_name" => "ElasticGraph::GraphQL::ClientResolvers::ViaHTTPHeaderTypo",
                "require_path" => "support/client_resolvers",
                "header_name" => "X-CLIENT-NAME"
              }
            })
          }.to raise_error NameError, a_string_including("uninitialized constant ElasticGraph::GraphQL::ClientResolvers::ViaHTTPHeaderTypo")
        end

        it "raises an error when given an extension that does not implement the right interface" do
          expect {
            Config.from_parsed_yaml("graphql" => {
              "default_page_size" => 27,
              "max_page_size" => 270,
              "client_resolver" => {
                "extension_name" => "ElasticGraph::GraphQL::ClientResolvers::Invalid",
                "require_path" => "support/client_resolvers",
                "header_name" => "X-CLIENT-NAME"
              }
            })
          }.to raise_error Errors::InvalidExtensionError, a_string_including("Missing instance methods: `resolve`")
        end
      end

      describe "#extension_settings" do
        it "is empty if the config YAML file contains no settings beyond the core ElasticGraph ones" do
          config = Config.from_parsed_yaml(parsed_test_settings_yaml)

          expect(config.extension_settings).to eq({})
        end

        it "includes any additional settings that aren't part of ElasticGraph's core configuration" do
          parsed_yaml = parsed_test_settings_yaml.merge(
            "ext1" => {"a" => 3, "b" => false},
            "ext2" => [12, 24]
          )

          config = Config.from_parsed_yaml(parsed_yaml)

          expect(config.extension_settings).to eq(
            "ext1" => {"a" => 3, "b" => false},
            "ext2" => [12, 24]
          )
        end
      end

      describe "#extension_modules", :in_temp_dir do
        it "loads the extension modules from disk" do
          File.write("eg_extension_module1.rb", <<~EOS)
            module EgExtensionModule1
            end
          EOS

          File.write("eg_extension_module2.rb", <<~EOS)
            module EgExtensionModule2
            end
          EOS

          extension_modules = extension_modules_from(<<~YAML)
            extension_modules:
              - require_path: ./eg_extension_module1
                extension_name: EgExtensionModule1
              - require_path: ./eg_extension_module2
                extension_name: EgExtensionModule2
          YAML

          expect(extension_modules).to eq([::EgExtensionModule1, ::EgExtensionModule2])
        end

        it "raises a clear error if the extension can't be loaded" do
          expect {
            extension_modules_from(<<~YAML)
              extension_modules:
                - require_path: ./not_real
                  extension_name: NotReal
            YAML
          }.to raise_error LoadError, a_string_including("not_real")
        end

        it "raises a clear error if the config is malformed" do
          expect {
            extension_modules_from(<<~YAML)
              extension_modules:
                - require: ./not_real
                  extension_name: NotReal
            YAML
          }.to raise_error a_string_including("require_path")

          File.write("eg_extension_module1.rb", <<~EOS)
            module EgExtensionModule1
            end
          EOS

          expect {
            extension_modules_from(<<~YAML)
              extension_modules:
                - require_path: ./eg_extension_module1
                  extension: EgExtensionModule1
            YAML
          }.to raise_error a_string_including("extension_name")
        end

        it "raises a clear error if the named extension is not a module" do
          File.write("eg_extension_class1.rb", <<~EOS)
            class EgExtensionClass1
            end
          EOS

          expect {
            extension_modules_from(<<~YAML)
              extension_modules:
                - require_path: ./eg_extension_class1
                  extension_name: EgExtensionClass1
            YAML
          }.to raise_error a_string_including("not a module")

          File.write("eg_extension_object1.rb", <<~EOS)
            EgExtensionObject1 = Object.new
          EOS

          expect {
            extension_modules_from(<<~YAML)
              extension_modules:
                - require_path: ./eg_extension_object1
                  extension_name: EgExtensionObject1
            YAML
          }.to raise_error a_string_including("not a class or module")
        end

        def load_config_from_yaml(yaml)
          yaml = <<~EOS
            default_page_size: 27
            max_page_size: 270
            #{yaml}
          EOS

          Config.from_parsed_yaml("graphql" => ::YAML.safe_load(yaml))
        end

        def extension_modules_from(yaml)
          load_config_from_yaml(yaml).extension_modules
        end
      end
    end
  end
end
