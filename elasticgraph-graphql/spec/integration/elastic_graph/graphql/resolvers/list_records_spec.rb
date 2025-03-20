# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/list_records"

module ElasticGraph
  class GraphQL
    module Resolvers
      RSpec.describe ListRecords, :factories, :uses_datastore, :resolver do
        context "when the field being resolved is a relay connection field" do
          let(:graphql) { build_graphql }

          it "wraps the datastore response in a relay connection adapter when the field is a relay connection field" do
            expect(resolve("Query", "widgets")).to be_a RelayConnection::GenericAdapter
          end
        end

        describe "sorting" do
          let(:graphql) { build_graphql }

          let(:widget1) { build(:widget, id: "w1", amount_cents: 100, created_at: "2019-06-01T00:00:00Z") }
          let(:widget2) { build(:widget, id: "w2", amount_cents: 200, created_at: "2019-06-02T00:00:00Z") }
          let(:widget3) { build(:widget, id: "w3", amount_cents: 200, created_at: "2019-06-03T00:00:00Z") }

          before do
            index_into(graphql, widget1, widget2, widget3)
          end

          it "respects a list of `order_by` options, supporting ascending and descending sorts" do
            results = resolve_nodes("Query", "widgets", order_by: ["amount_cents_DESC", "created_at_ASC"])
            expect(results.map { |r| r.fetch("id") }).to eq ["w2", "w3", "w1"]

            results = resolve_nodes("Query", "widgets", order_by: ["amount_cents_ASC", "created_at_DESC"])
            expect(results.map { |r| r.fetch("id") }).to eq ["w1", "w3", "w2"]
          end
        end

        describe "filtering" do
          let(:graphql) { build_graphql }

          let(:widget1) { build(:widget, name: "w1", amount_cents: 100, id: "w1", created_at: "2021-01-01T12:00:00Z") }
          let(:widget2a) { build(:widget, name: "w2", amount_cents: 100, id: "w2a", created_at: "2021-02-01T12:00:00Z") }
          let(:widget2b) { build(:widget, name: "w2", amount_cents: 200, id: "w2b", created_at: "2021-02-01T12:00:00Z") }
          let(:widget3) { build(:widget, name: "w3", amount_cents: 300, id: "w3", created_at: "2021-03-01T12:00:00Z") }

          before do
            index_into(graphql, widget1, widget2a, widget2b, widget3)
          end

          it "supports filtering by a list of one value" do
            results = resolve_nodes("Query", "widgets", filter: {id: {equal_to_any_of: [widget1.fetch(:id)]}})
            expect(results.map { |r| r.fetch("id") }).to contain_exactly(widget1.fetch(:id))

            results = resolve_nodes("Query", "widgets", filter: {name: {equal_to_any_of: ["w2"]}})
            expect(results.map { |r| r.fetch("id") }).to contain_exactly(widget2a.fetch(:id), widget2b.fetch(:id))
          end

          it "supports filtering by a list of multiple values" do
            results = resolve_nodes("Query", "widgets", filter: {id: {equal_to_any_of: [widget1.fetch(:id), widget3.fetch(:id)]}})
            expect(results.map { |r| r.fetch("id") }).to contain_exactly(widget1.fetch(:id), widget3.fetch(:id))

            results = resolve_nodes("Query", "widgets", filter: {name: {equal_to_any_of: ["w2", "w1"]}})
            expect(results.map { |r| r.fetch("id") }).to contain_exactly(widget1.fetch(:id), widget2a.fetch(:id), widget2b.fetch(:id))
          end

          it "supports default sort" do
            results = resolve_nodes("Query", "widgets", filter: {id: {equal_to_any_of: ["w3", "w2b", "w1"]}})
            expect(results.map { |r| r.fetch("id") }).to eq([widget3.fetch(:id), widget2b.fetch(:id), widget1.fetch(:id)])
          end

          it "supports combining filters on more than one field" do
            results = resolve_nodes("Query", "widgets", filter: {
              name: {equal_to_any_of: ["w2", "w3"]},
              amount_cents: {equal_to_any_of: [100, 400]}
            })

            expect(results.map { |r| r.fetch("id") }).to contain_exactly(widget2a.fetch(:id))
          end
        end

        # Override `resolve` to force `id` to always be requested since the specs rely on it.
        def resolve(*args, **options)
          super(*args, query_overrides: {requested_fields: ["id"]}, **options)
        end

        def resolve_nodes(...)
          resolve(...).edges.map(&:node)
        end
      end
    end
  end
end
