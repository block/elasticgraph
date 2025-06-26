# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "rack/test"
require "json"

RSpec.shared_context "rack app support" do
  include Rack::Test::Methods
  let(:app) { ::Rack::Lint.new(app_to_test) }

  def last_parsed_response
    JSON.parse(last_response.body)
  end

  def with_header(name, value)
    header name, value
    yield
  ensure
    header name, nil
  end

  def call_graphql_query(query)
    call_graphql(JSON.generate(query: query))
  end

  def post_json(path, body)
    with_header "Content-Type", "application/json" do
      with_header "Accept", "application/json" do
        post path, body
      end
    end
  end

  def call_graphql(body)
    post_json "/", body
    expect(last_response).to be_ok

    last_parsed_response.tap do |parsed_response|
      expect(parsed_response["errors"]).to eq([]).or eq(nil)
    end
  end
end

RSpec.configure do |rspec|
  rspec.include_context "rack app support", :rack_app
end
