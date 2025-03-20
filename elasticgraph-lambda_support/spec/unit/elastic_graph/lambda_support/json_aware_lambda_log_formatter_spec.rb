# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/lambda_support/json_aware_lambda_log_formatter"
require "logger"
require "stringio"

module ElasticGraph
  module LambdaSupport
    RSpec.describe JSONAwareLambdaLogFormatter do
      let(:logger_formatter) { JSONAwareLambdaLogFormatter.new }
      let(:our_logger_output) { ::StringIO.new }
      let(:our_logger) { ::Logger.new(our_logger_output, formatter: logger_formatter) }

      it "logs string with expected format and data" do
        logger_formatter.datetime_format = "static_for_tests"
        our_logger.info "some message"

        expect(our_logger_output.string).to eq("I, [static_for_tests ##{Process.pid}]  INFO  -- : some message")
      end

      it "logs hashes of data as well-formed JSON so that we can apply cloudwatch metric filters to it" do
        our_logger.info(some: "data")
        json_data = ::JSON.parse(our_logger_output.string)
        expect(json_data).to include(
          "process" => $$,
          "severity" => "INFO",
          "some" => "data"
        )
      end
    end
  end
end
