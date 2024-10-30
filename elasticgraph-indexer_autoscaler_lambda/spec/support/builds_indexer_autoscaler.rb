# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer_autoscaler_lambda"
require "elastic_graph/spec_support/builds_datastore_core"

module ElasticGraph
  module BuildsIndexerAutoscalerLambda
    include BuildsDatastoreCore

    def build_indexer_autoscaler(
      sqs_client: nil,
      lambda_client: nil,
      cloudwatch_client: nil,
      **datastore_core_options,
      &customize_datastore_config
    )
      datastore_core = build_datastore_core(
        for_context: :autoscaling,
        **datastore_core_options,
        &customize_datastore_config
      )

      IndexerAutoscalerLambda.new(
        sqs_client: sqs_client,
        lambda_client: lambda_client,
        cloudwatch_client: cloudwatch_client,
        datastore_core: datastore_core
      )
    end
  end
end
