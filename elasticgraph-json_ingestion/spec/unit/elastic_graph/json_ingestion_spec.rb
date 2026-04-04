# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion"

module ElasticGraph
  RSpec.describe JSONIngestion do
    it "exposes the expected module name" do
      expect(described_class.name).to eq "ElasticGraph::JSONIngestion"
    end
  end
end
