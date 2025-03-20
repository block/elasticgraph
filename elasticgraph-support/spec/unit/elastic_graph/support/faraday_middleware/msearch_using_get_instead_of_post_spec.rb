# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/faraday_middleware/msearch_using_get_instead_of_post"
require "faraday"

module ElasticGraph
  module Support
    module FaradayMiddleware
      RSpec.describe MSearchUsingGetInsteadOfPost, :no_vcr do
        it "converts a POST to a path ending in `_msearch` to a GET since msearch is read-only" do
          faraday = stubbed_faraday do |stub|
            stub.get("/foo/bar/_msearch") do |env|
              text_response("GET msearch")
            end
          end

          response = faraday.post("/foo/bar/_msearch") do |req|
            req.body = "some body"
          end

          expect(response.body).to eq "GET msearch"
        end

        it "leaves a POST to a non-msearch URL unchanged" do
          faraday = stubbed_faraday do |stub|
            stub.post("/foo/bar/other") do |env|
              text_response("POST other")
            end
          end

          response = faraday.post("/foo/bar/other") do |req|
            req.body = "some body"
          end

          expect(response.body).to eq "POST other"
        end

        it "leaves a GET to a path ending in `_msearch` unchanged" do
          faraday = stubbed_faraday do |stub|
            stub.get("/foo/bar/_msearch") do |env|
              text_response("GET msearch")
            end
          end

          response = faraday.get("/foo/bar/_msearch")

          expect(response.body).to eq "GET msearch"
        end

        it "does not treat a path like `/foo/bar_msearch` as an msearch path" do
          faraday = stubbed_faraday do |stub|
            stub.post("/foo/bar_msearch") do |env|
              text_response("POST bar_msearch")
            end
          end

          response = faraday.post("/foo/bar_msearch") do |req|
            req.body = "some body"
          end

          expect(response.body).to eq "POST bar_msearch"
        end

        def stubbed_faraday(&stub_block)
          ::Faraday.new do |faraday|
            faraday.use MSearchUsingGetInsteadOfPost
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
