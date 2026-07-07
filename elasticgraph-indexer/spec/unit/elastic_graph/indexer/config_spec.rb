# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/config"
require "yaml"

module ElasticGraph
  class Indexer
    RSpec.describe Config do
      it "raises an error when given an unrecognized config setting" do
        expect {
          Config.from_parsed_yaml("indexer" => {
            "latency_slo_thresholds_by_timestamp_in_ms" => {},
            "fake_setting" => 23
          })
        }.to raise_error Errors::ConfigError, a_string_including("fake_setting")
      end

      it "converts the values of `skip_derived_indexing_type_updates` to a set" do
        config = Config.from_parsed_yaml("indexer" => {
          "latency_slo_thresholds_by_timestamp_in_ms" => {},
          "skip_derived_indexing_type_updates" => {
            "WidgetCurrency" => ["USD"]
          }
        })

        expect(config.skip_derived_indexing_type_updates).to eq("WidgetCurrency" => ["USD"].to_set)
      end

      it "leaves the indexing event decoder unconfigured by default" do
        expect(Config.new.indexing_event_decoder).to be nil
      end

      it "loads a configured indexing event decoder" do
        config = Config.from_parsed_yaml("indexer" => {
          "indexing_event_decoder" => {
            "name" => "ExampleIndexingEventDecoder",
            "require_path" => "support/example_extensions/indexing_event_decoder",
            "config" => {"delimiter" => "|"}
          }
        })

        expect(config.indexing_event_decoder.extension_class).to be(ExampleIndexingEventDecoder)
        expect(config.indexing_event_decoder.config).to eq({"delimiter" => "|"})
      end

      it "verifies that a configured indexing event decoder implements the expected interface" do
        expect {
          Config.from_parsed_yaml("indexer" => {
            "indexing_event_decoder" => {
              "name" => "InvalidIndexingEventDecoder",
              "require_path" => "support/example_extensions/indexing_event_decoder"
            }
          })
        }.to raise_error Errors::InvalidExtensionError, a_string_including("InvalidIndexingEventDecoder", "Missing instance methods: `decode`")
      end
    end
  end
end
