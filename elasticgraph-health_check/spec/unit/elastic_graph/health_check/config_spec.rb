# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/health_check/config"
require "yaml"

module ElasticGraph
  module HealthCheck
    RSpec.describe Config do
      it "builds from parsed YAML correctly" do
        parsed_yaml = ::YAML.safe_load(<<~EOS)
          health_check:
            clusters_to_consider: [widgets1, components2]
            data_recency_checks:
              Widget:
                expected_max_recency_seconds: 30
                timestamp_field: created_at
        EOS

        config = Config.from_parsed_yaml(parsed_yaml)

        expect(config).to eq(Config.new(
          clusters_to_consider: ["widgets1", "components2"],
          data_recency_checks: {
            "Widget" => {
              "expected_max_recency_seconds" => 30,
              "timestamp_field" => "created_at"
            }
          }
        ))

        # Verify the converted values
        expect(config.data_recency_checks["Widget"]).to be_a(Config::DataRecencyCheck)
        expect(config.data_recency_checks["Widget"].expected_max_recency_seconds).to eq(30)
        expect(config.data_recency_checks["Widget"].timestamp_field).to eq("created_at")
      end

      it "returns nil if the config settings have no `health_check` key" do
        config = Config.from_parsed_yaml({})
        expect(config).to be_nil
      end

      it "can be instantiated with default values" do
        config = Config.new
        expect(config.clusters_to_consider).to be_empty
        expect(config.data_recency_checks).to be_empty
        expect(config.timeout_ms).to eq(5000)
      end

      it "allows configuring a custom timeout_ms" do
        config = Config.new(timeout_ms: 3000)
        expect(config.timeout_ms).to eq(3000)
      end

      it "parses timeout_ms from YAML" do
        parsed_yaml = ::YAML.safe_load(<<~EOS)
          health_check:
            clusters_to_consider: []
            data_recency_checks: {}
            timeout_ms: 10000
        EOS

        config = Config.from_parsed_yaml(parsed_yaml)
        expect(config.timeout_ms).to eq(10000)
      end
    end
  end
end
