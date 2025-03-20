# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer_autoscaler_lambda"
require "elastic_graph/spec_support/lambda_function"
require "support/builds_indexer_autoscaler"

module ElasticGraph
  RSpec.describe IndexerAutoscalerLambda do
    include BuildsIndexerAutoscalerLambda
    include_context "lambda function"

    it "returns non-nil values from each attribute" do
      expect_to_return_non_nil_values_from_all_attributes(build_indexer_autoscaler)
    end

    describe ".from_parsed_yaml" do
      it "builds an IndexerAutoscaler instance from the contents of a YAML settings file" do
        customization_block = ->(conn) {}
        indexer_autoscaler = IndexerAutoscalerLambda.from_parsed_yaml(parsed_test_settings_yaml, &customization_block)

        expect(indexer_autoscaler).to be_a(IndexerAutoscalerLambda)
        expect(indexer_autoscaler.datastore_core.client_customization_block).to be(customization_block)
      end
    end
  end
end
