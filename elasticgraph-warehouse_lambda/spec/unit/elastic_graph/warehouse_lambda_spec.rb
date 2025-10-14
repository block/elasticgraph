# frozen_string_literal: true

require "elastic_graph/spec_support/lambda_function"
require "elastic_graph/warehouse_lambda"

module ElasticGraph
  RSpec.describe WarehouseLambda do
    include_context "lambda function"

    it "returns non-nil values from each attribute" do
      warehouse_lambda = WarehouseLambda.from_env

      expect(warehouse_lambda).to be_a(WarehouseLambda)
      expect_to_return_non_nil_values_from_all_attributes(warehouse_lambda)
    end
  end
end
