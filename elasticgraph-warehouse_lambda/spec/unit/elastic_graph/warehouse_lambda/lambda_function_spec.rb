# frozen_string_literal: true
# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
require "elastic_graph/spec_support/lambda_function"

RSpec.describe "Warehouse lambda function" do
  include_context "lambda function", config_overrides_in_yaml: {"warehouse" => {"s3_path_prefix" => "Data001"}}

  # Provide the S3 bucket env var expected by the lambda under test.
  around do |ex|
    with_env({"DATAWAREHOUSE_S3_BUCKET_NAME" => "warehouse-bucket"}) { ex.run }
  end

  it "ingests data" do
    expect_loading_lambda_to_define_constant(
      lambda: "elastic_graph/warehouse_lambda/lambda_function.rb",
      const: :ElasticGraphWarehouse
    ) do |lambda_function|
      response = lambda_function.handle_request(event: {"Records" => []}, context: {})
      expect(response).to eq({"batchItemFailures" => []})
    end
  end
end
