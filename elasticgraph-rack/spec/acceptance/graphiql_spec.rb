# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/rack"
require "elastic_graph/rack/graphiql"

module ElasticGraph::Rack
  RSpec.describe GraphiQL, :rack_app do
    let(:app_to_test) { GraphiQL.new(build_graphql) }

    it "serves a GraphiQL UI at the root" do
      get "/"

      expect(last_response).to be_ok_with_title "ElasticGraph GraphiQL"
    end

    it "fails with a clear error if the GraphiQL assets cannot be extracted" do
      allow(::Open3).to receive(:capture3).with(a_string_starting_with("tar ")).and_return(
        ["boom stdout", "boom stderr", instance_double(::Process::Status, success?: false, exitstatus: 17)]
      )

      expect {
        get "/"
      }.to raise_error a_string_including("boom stdout", "boom stderr")
    end

    def be_ok_with_title(title)
      have_attributes(status: 200, body: a_string_including("<title>#{title}</title>"))
    end
  end
end
