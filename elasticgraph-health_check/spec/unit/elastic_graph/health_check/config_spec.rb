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
          clusters_to_consider: [widgets1, components2]
          data_recency_checks:
            Widget:
              expected_max_recency_seconds: 30
              timestamp_field: created_at
        EOS

        config = Config.from_parsed_yaml("health_check" => parsed_yaml)

        expect(config).to eq(Config.new(
          clusters_to_consider: ["widgets1", "components2"],
          data_recency_checks: {
            "Widget" => Config::DataRecencyCheck.new(
              expected_max_recency_seconds: 30,
              timestamp_field: "created_at"
            )
          }
        ))
      end

      it "returns an empty, benign config instance if the config settings have no `health_check` key" do
        config = Config.from_parsed_yaml({})

        expect(config.clusters_to_consider).to be_empty
        expect(config.data_recency_checks).to be_empty
      end
    end
  end
end
