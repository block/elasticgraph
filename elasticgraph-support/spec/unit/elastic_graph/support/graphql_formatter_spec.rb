# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/graphql_formatter"

module ElasticGraph
  module Support
    RSpec.describe GraphQLFormatter do
      describe "#format_args" do
        include GraphQLFormatter

        it "formats an empty arg hash as an empty string" do
          formatted = GraphQLFormatter.format_args

          expect(formatted).to eq ""
        end

        it "formats numbers, booleans, and string args correctly" do
          formatted = GraphQLFormatter.format_args(foo: 3, bar: false, bazz: true, quix: "abc")

          expect(formatted).to eq('(foo: 3, bar: false, bazz: true, quix: "abc")')
        end

        it "formats nested arrays and nested objects correctly" do
          formatted = GraphQLFormatter.format_args(foo: [1, 2], bar: [{a: 1}, {a: 2}], bazz: {c: 12})

          expect(formatted).to eq("(foo: [1, 2], bar: [{a: 1}, {a: 2}], bazz: {c: 12})")
        end

        it "formats symbols as GraphQL enum values" do
          formatted = GraphQLFormatter.format_args(foo: :bar, bazz: "bar")

          expect(formatted).to eq('(foo: bar, bazz: "bar")')
        end
      end
    end
  end
end
