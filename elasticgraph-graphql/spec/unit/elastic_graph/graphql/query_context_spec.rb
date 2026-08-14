# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/graphql/query_context"

module ElasticGraph
  class GraphQL
    RSpec.describe QueryContext do
      let(:context) do
        described_class.new(
          query: instance_double(::GraphQL::Query, fingerprint: "GetColors/abc123"),
          schema: Class.new(::GraphQL::Schema),
          values: {}
        )
      end

      describe "#[] and #fetch" do
        it "raises a helpful error for a removed magic context key, directing to the replacement accessor" do
          expect {
            context[:monotonic_clock_deadline]
          }.to raise_error(Errors::ConfigError, a_string_including("context.monotonic_clock_deadline"))

          expect {
            context.fetch(:monotonic_clock_deadline)
          }.to raise_error(Errors::ConfigError, a_string_including("context.monotonic_clock_deadline"))
        end

        it "still works normally for keys that were never replaced by a typed accessor" do
          context[:visibility_profile] = "public"

          expect(context[:visibility_profile]).to eq("public")
          expect(context.fetch(:visibility_profile)).to eq("public")
        end
      end
    end
  end
end
