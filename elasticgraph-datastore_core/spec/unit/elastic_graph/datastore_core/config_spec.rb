# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/config"
require "elastic_graph/elasticsearch/client"
require "elastic_graph/opensearch/client"
require "yaml"

module ElasticGraph
  class DatastoreCore
    RSpec.describe Config do
      it "populates every config field" do
        config = config_from_yaml(<<~YAML)
          client_faraday_adapter:
            name: net_http
          clusters:
            main1:
              url: http://example.com/1234
              backend: elasticsearch
              settings:
                foo: 23
          index_definitions:
            widgets:
              query_cluster: "main"
              index_into_clusters: ["main"]
              ignore_routing_values: []
              setting_overrides: {}
              setting_overrides_by_timestamp: {}
              custom_timestamp_ranges: {}
          log_traffic: true
          max_client_retries: 3
        YAML

        expect(config.client_faraday_adapter).to eq Configuration::ClientFaradayAdapter.new(
          name: :net_http,
          require: nil
        )
        expect(config.clusters).to eq("main1" => Configuration::ClusterDefinition.new(
          url: "http://example.com/1234",
          backend_client_class: Elasticsearch::Client,
          settings: {"foo" => 23}
        ))
        expect(config.index_definitions).to eq("widgets" => Configuration::IndexDefinition.new(
          ignore_routing_values: [],
          query_cluster: "main",
          index_into_clusters: ["main"],
          setting_overrides: {},
          setting_overrides_by_timestamp: {},
          custom_timestamp_ranges: []
        ))
        expect(config.log_traffic).to eq true
        expect(config.max_client_retries).to eq 3
      end

      it "provides useful defaults for config settings that rarely need to be set" do
        config = config_from_yaml(<<~YAML)
          client_faraday_adapter:
          clusters:
            main1:
              url: http://example.com/1234
              backend: opensearch
              settings:
                foo: 23
          index_definitions:
            widgets:
              query_cluster: "main"
              index_into_clusters: ["main"]
              ignore_routing_values: []
              setting_overrides: {}
              setting_overrides_by_timestamp: {}
              custom_timestamp_ranges: {}
        YAML

        expect(config.client_faraday_adapter).to eq Configuration::ClientFaradayAdapter.new(
          name: nil,
          require: nil
        )
        expect(config.clusters).to eq("main1" => Configuration::ClusterDefinition.new(
          url: "http://example.com/1234",
          backend_client_class: OpenSearch::Client,
          settings: {"foo" => 23}
        ))
        expect(config.index_definitions).to eq("widgets" => Configuration::IndexDefinition.new(
          ignore_routing_values: [],
          query_cluster: "main",
          index_into_clusters: ["main"],
          setting_overrides: {},
          setting_overrides_by_timestamp: {},
          custom_timestamp_ranges: []
        ))
        expect(config.log_traffic).to eq false
        expect(config.max_client_retries).to eq 3
      end

      it "surfaces misspellings in `backend`" do
        expect {
          config_from_yaml(<<~YAML)
            client_faraday_adapter:
            clusters:
              main1:
                url: http://example.com/1234
                backend: opensaerch
                settings:
                  foo: 23
            index_definitions:
              widgets:
                query_cluster: "main"
                index_into_clusters: ["main"]
                ignore_routing_values: []
                setting_overrides: {}
                setting_overrides_by_timestamp: {}
                custom_timestamp_ranges: {}
          YAML
        }.to raise_error Errors::ConfigError, a_string_including("Unknown `datastore.clusters` backend: `opensaerch`. Valid backends are `elasticsearch` and `opensearch`.")
      end

      it "surfaces any unknown root config settings" do
        expect {
          config_from_yaml(<<~YAML)
            not_a_real_setting: 23
            client_faraday_adapter:
              name: net_http
            clusters:
              main1:
                url: http://example.com/1234
                backend: elasticsearch
                settings:
                  foo: 23
            index_definitions:
              widgets:
                query_cluster: "main"
                index_into_clusters: ["main"]
                ignore_routing_values: []
                setting_overrides: {}
                setting_overrides_by_timestamp: {}
                custom_timestamp_ranges: {}
          YAML
        }.to raise_error Errors::ConfigError, a_string_including("not_a_real_setting")
      end

      it "surfaces unknown clusters config settings" do
        expect {
          config_from_yaml(<<~YAML)
            client_faraday_adapter:
              name: net_http
            clusters:
              main1:
                url: http://example.com/1234
                backend: elasticsearch
                not_a_real_setting: 23
                settings:
                  foo: 23
            index_definitions:
              widgets:
                query_cluster: "main"
                index_into_clusters: ["main"]
                ignore_routing_values: []
                setting_overrides: {}
                setting_overrides_by_timestamp: {}
                custom_timestamp_ranges: {}
          YAML
        }.to raise_error Errors::ConfigError, a_string_including("not_a_real_setting")
      end

      it "surfaces unknown index definition config settings" do
        expect {
          config_from_yaml(<<~YAML)
            client_faraday_adapter:
              name: net_http
            clusters:
              main1:
                url: http://example.com/1234
                backend: opensearch
                settings:
                  foo: 23
            index_definitions:
              widgets:
                not_a_real_setting: 23
                query_cluster: "main"
                index_into_clusters: ["main"]
                ignore_routing_values: []
                setting_overrides: {}
                setting_overrides_by_timestamp: {}
                custom_timestamp_ranges: {}
          YAML
        }.to raise_error ArgumentError, a_string_including("not_a_real_setting")
      end

      it "surfaces unknown client_faraday_adapter config settings" do
        expect {
          config_from_yaml(<<~YAML)
            client_faraday_adapter:
              name: net_http
              not_a_real_setting: foo
            clusters:
              main1:
                url: http://example.com/1234
                backend: elasticsearch
                settings:
                  foo: 23
            index_definitions:
              widgets:
                query_cluster: "main"
                index_into_clusters: ["main"]
                ignore_routing_values: []
                setting_overrides: {}
                setting_overrides_by_timestamp: {}
                custom_timestamp_ranges: {}
          YAML
        }.to raise_error Errors::ConfigError, a_string_including("not_a_real_setting")
      end

      describe "index_definitions.custom_timestamp_ranges" do
        it "builds a `CustomTimestampRange` object from the provided YAML" do
          range = only_custom_range_from(<<~YAML)
            - index_name_suffix: "before_2015"
              lt: "2015-01-01T00:00:00Z"
              setting_overrides:
                number_of_shards: 17
          YAML

          expect(range.index_name_suffix).to eq "before_2015"
          expect(range.setting_overrides).to eq({"number_of_shards" => 17})
          expect(range.time_set).to eq(Support::TimeSet.of_range(lt: ::Time.iso8601("2015-01-01T00:00:00Z")))
        end

        it "correctly supports `lt`" do
          range = only_custom_range_from(<<~YAML)
            - index_name_suffix: "before_2015"
              lt: "2015-01-01T00:00:00Z"
              setting_overrides:
                number_of_shards: 17
          YAML

          expect(range.time_set).to eq(Support::TimeSet.of_range(lt: ::Time.iso8601("2015-01-01T00:00:00Z")))
        end

        it "correctly supports `lte`" do
          range = only_custom_range_from(<<~YAML)
            - index_name_suffix: "before_2015"
              lte: "2015-01-01T00:00:00Z"
              setting_overrides:
                number_of_shards: 17
          YAML

          expect(range.time_set).to eq(Support::TimeSet.of_range(lte: ::Time.iso8601("2015-01-01T00:00:00Z")))
        end

        it "correctly supports `gt`" do
          range = only_custom_range_from(<<~YAML)
            - index_name_suffix: "before_2015"
              gt: "2015-01-01T00:00:00Z"
              setting_overrides:
                number_of_shards: 17
          YAML

          expect(range.time_set).to eq(Support::TimeSet.of_range(gt: ::Time.iso8601("2015-01-01T00:00:00Z")))
        end

        it "correctly supports `gte`" do
          range = only_custom_range_from(<<~YAML)
            - index_name_suffix: "before_2015"
              gte: "2015-01-01T00:00:00Z"
              setting_overrides:
                number_of_shards: 17
          YAML

          expect(range.time_set).to eq(Support::TimeSet.of_range(gte: ::Time.iso8601("2015-01-01T00:00:00Z")))
        end

        it "supports ranges having multiple boundary conditions" do
          range = only_custom_range_from(<<~YAML)
            - index_name_suffix: "before_2015"
              gte: "2015-01-01T00:00:00Z"
              lt: "2020-01-01T00:00:00Z"
              setting_overrides:
                number_of_shards: 17
          YAML

          expect(range.time_set).to eq(Support::TimeSet.of_range(
            gte: ::Time.iso8601("2015-01-01T00:00:00Z"),
            lt: ::Time.iso8601("2020-01-01T00:00:00Z")
          ))
        end

        it "supports identifying the range a timestamp is covered by" do
          index_def = index_definition_for(<<~YAML)
            - index_name_suffix: "before_2015"
              lt: "2015-01-01T00:00:00Z"
              setting_overrides:
                number_of_shards: 17
            - index_name_suffix: "2016_and_2017"
              gte: "2016-01-01T00:00:00Z"
              lt: "2018-01-01T00:00:00Z"
              setting_overrides:
                number_of_shards: 17
          YAML

          expect(index_def.custom_timestamp_range_for(Time.iso8601("2014-01-01T00:00:00Z")).index_name_suffix).to eq "before_2015"
          expect(index_def.custom_timestamp_range_for(Time.iso8601("2015-01-01T00:00:00Z"))).to eq nil
          expect(index_def.custom_timestamp_range_for(Time.iso8601("2016-01-01T00:00:00Z")).index_name_suffix).to eq "2016_and_2017"
          expect(index_def.custom_timestamp_range_for(Time.iso8601("2017-01-01T00:00:00Z")).index_name_suffix).to eq "2016_and_2017"
          expect(index_def.custom_timestamp_range_for(Time.iso8601("2018-01-01T00:00:00Z"))).to eq nil
        end

        it "raises an error when a boundary timestamp cannot be parsed" do
          expect {
            only_custom_range_from(<<~YAML)
              - index_name_suffix: "before_2015"
                gte: "2015-13-01T00:00:00Z"
                setting_overrides:
                  number_of_shards: 17
            YAML
          }.to raise_error ArgumentError, a_string_including("out of range")
        end

        it "raises an error when a range is invalid due to no timestamps being covered by it" do
          expect {
            only_custom_range_from(<<~YAML)
              - index_name_suffix: "before_2015"
                gte: "2020-01-01T00:00:00Z"
                lt: "2015-01-01T00:00:00Z"
                setting_overrides:
                  number_of_shards: 17
            YAML
          }.to raise_error Errors::ConfigError, a_string_including("is invalid")
        end

        it "raises an error if a custom range lacks any boundaries" do
          expect {
            index_definition_for(<<~YAML)
              - index_name_suffix: "before_2015"
                setting_overrides:
                  number_of_shards: 17
            YAML
          }.to raise_error Errors::ConfigSettingNotSetError, a_string_including("before_2015", "lacks boundary definitions")
        end

        it "raises an error if custom timestamp ranges overlap" do
          expect {
            index_definition_for(<<~YAML)
              - index_name_suffix: "before_2015"
                lte: "2015-01-01T00:00:00Z"
                setting_overrides:
                  number_of_shards: 17
              - index_name_suffix: "2015_and_2016"
                gte: "2015-01-01T00:00:00Z"
                lt: "2016-01-01T00:00:00Z"
                setting_overrides:
                  number_of_shards: 17
            YAML
          }.to raise_error Errors::ConfigError, a_string_including("are not disjoint")
        end

        it "raises an error when given an unrecognized config setting" do
          expect {
            only_custom_range_from(<<~YAML)
              - index_name_suffix: "before_2015"
                gtf: "2020-01-01T00:00:00Z"
                lt: "2015-01-01T00:00:00Z"
                setting_overrides:
                  number_of_shards: 17
            YAML
          }.to raise_error ArgumentError, a_string_including("gtf")
        end

        def only_custom_range_from(yaml_section)
          ranges = index_definition_for(yaml_section).custom_timestamp_ranges
          expect(ranges.size).to eq 1
          ranges.first
        end

        def index_definition_for(yaml_section)
          yaml = <<~YAML
            client_faraday_adapter:
              name: net_http
            clusters: {}
            log_traffic: false
            max_client_retries: 3
            index_definitions:
              widgets:
                query_cluster: "main"
                index_into_clusters: ["main"]
                ignore_routing_values: []
                setting_overrides: {}
                setting_overrides_by_timestamp: {}
                custom_timestamp_ranges:
                  #{yaml_section.split("\n").join("\n" + (" " * 6))}
          YAML

          config = config_from_yaml(yaml)
          config.index_definitions.fetch("widgets")
        end
      end

      def config_from_yaml(yaml_string)
        Config.from_parsed_yaml("datastore" => ::YAML.safe_load(yaml_string))
      end
    end
  end
end
