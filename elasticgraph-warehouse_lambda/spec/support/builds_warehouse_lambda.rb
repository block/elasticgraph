# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/config"
require "elastic_graph/spec_support/builds_datastore_core"
require "elastic_graph/warehouse_lambda"

module ElasticGraph
  module BuildsWarehouseLambda
    include BuildsDatastoreCore

    def build_warehouse_lambda(
      s3_path_prefix: "Data0001",
      s3_bucket_name: "warehouse-bucket",
      aws_region: "us-west-2",
      s3_client: nil,
      clock: ::Time,
      **datastore_core_options,
      &customize_datastore_config
    )
      WarehouseLambda.new(
        config: WarehouseLambda::Config.new(
          s3_path_prefix: s3_path_prefix,
          s3_bucket_name: s3_bucket_name,
          aws_region: aws_region
        ),
        indexer_config: Indexer::Config.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml),
        datastore_core: build_datastore_core(**datastore_core_options, &customize_datastore_config),
        clock: clock,
        s3_client: s3_client
      )
    end
  end
end
