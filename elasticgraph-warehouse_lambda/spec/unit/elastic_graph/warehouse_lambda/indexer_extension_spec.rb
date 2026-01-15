# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/warehouse_lambda/indexer_extension"
require "elastic_graph/warehouse_lambda"
require "elastic_graph/indexer"

module ElasticGraph
  class WarehouseLambda
    RSpec.describe IndexerExtension do
      it "redirects datastore_router to warehouse_dumper" do
        indexer = ::ElasticGraph::Indexer.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml)
        warehouse_lambda = instance_double(WarehouseLambda)
        warehouse_dumper = instance_double("WarehouseDumper")

        allow(warehouse_lambda).to receive(:warehouse_dumper).and_return(warehouse_dumper)

        indexer.extend IndexerExtension
        indexer.warehouse_lambda = warehouse_lambda

        expect(indexer.datastore_router).to eq warehouse_dumper
      end

      it "allows setting and getting warehouse_lambda" do
        indexer = ::ElasticGraph::Indexer.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml)
        warehouse_lambda = instance_double(WarehouseLambda)

        indexer.extend IndexerExtension
        indexer.warehouse_lambda = warehouse_lambda

        expect(indexer.warehouse_lambda).to eq warehouse_lambda
      end
    end
  end
end
