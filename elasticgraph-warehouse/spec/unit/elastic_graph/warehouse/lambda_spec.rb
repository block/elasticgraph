# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/lambda_function"
require "elastic_graph/warehouse/lambda"

module ElasticGraph
  module Warehouse
    RSpec.describe Lambda do
      include_context "lambda function", config_overrides_in_yaml: {"warehouse" => {"s3_path_prefix" => "TestPrefix"}}

      # Provide the S3 bucket env var expected by the lambda under test.
      around do |ex|
        with_env({"DATAWAREHOUSE_S3_BUCKET_NAME" => "warehouse-bucket"}) { ex.run }
      end

      it "returns non-nil values from each attribute" do
        warehouse_lambda = Lambda.from_env

        expect(warehouse_lambda).to be_a(Lambda)
        expect_to_return_non_nil_values_from_all_attributes(warehouse_lambda)
      end
    end
  end
end
