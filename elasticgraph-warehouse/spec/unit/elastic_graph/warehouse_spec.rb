# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse"

module ElasticGraph
  RSpec.describe Warehouse do
    it "defines the DATA_WAREHOUSE_FILE constant" do
      expect(Warehouse::DATA_WAREHOUSE_FILE).to eq("data_warehouse.yaml")
    end
  end
end
