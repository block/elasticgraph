# frozen_string_literal: true

# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#

require "elastic_graph/warehouse_lambda/config"
require "yaml"

module ElasticGraph
  class WarehouseLambda
    RSpec.describe Config do
      it "raises an error when given an unrecognized config setting" do
        expect {
          Config.from_parsed_yaml("warehouse" => {
            "s3_path_prefix" => "PREFIX",
            "fake_setting" => 23
          })
        }.to raise_error ::ElasticGraph::Errors::ConfigError, a_string_including("fake_setting")
      end
    end
  end
end
