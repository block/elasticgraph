# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/faraday_middleware/support_timeouts"
require "faraday"

module ElasticGraph
  module Support
    module FaradayMiddleware
      RSpec.describe SupportTimeouts, :no_vcr do
        it "sets the request timeout if the TIMEOUT_MS_HEADER is present" do
          faraday = stubbed_faraday do |stub|
            stub.get("/foo/bar") do |env|
              expect(env.request.timeout).to eq 10
              text_response("GET bar")
            end
          end

          response = faraday.get("/foo/bar") do |req|
            req.headers[TIMEOUT_MS_HEADER] = "10000"
          end

          expect(response.body).to eq "GET bar"
        end

        it "does not set the request timeout if the TIMEOUT_MS_HEADER is not present" do
          faraday = stubbed_faraday do |stub|
            stub.get("/foo/bar") do |env|
              expect(env.request.timeout).to be nil
              text_response("GET bar")
            end
          end

          response = faraday.get("/foo/bar")

          expect(response.body).to eq "GET bar"
        end

        it "converts a `Faraday::TimeoutError` to a `Errors::RequestExceededDeadlineError`" do
          faraday = stubbed_faraday do |stub|
            stub.get("/foo/bar") do |env|
              raise ::Faraday::TimeoutError
            end
          end

          expect {
            faraday.get("/foo/bar") do |req|
              req.headers[TIMEOUT_MS_HEADER] = "10000"
            end
          }.to raise_error Errors::RequestExceededDeadlineError, "Datastore request exceeded timeout of 10000 ms."
        end

        def stubbed_faraday(&stub_block)
          ::Faraday.new do |faraday|
            faraday.use SupportTimeouts
            faraday.adapter(:test, &stub_block)
          end
        end

        def text_response(text)
          [200, {"Content-Type" => "text/plain"}, text]
        end
      end
    end
  end
end
