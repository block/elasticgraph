# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/get_record_field_value"

module ElasticGraph
  class GraphQL
    module Resolvers
      module RelayConnection
        # Note: while this file is `array_adapter_spec.rb`, the describe block below
        # must use `GetRecordFieldValue` so we can leverage the handy `resolver` support
        # (since `GetRecordFieldValue` is a resolver, but `ArrayAdapter` is not).
        # It still primarily exercises the `ArrayAdapter` class defined in `array_adapter.rb`,
        # but does so via the `GetRecordFieldValue` resolver, which has the added benefit
        # of also verifying that `GetRecordFieldValue` builds `ArrayAdapter` properly.
        RSpec.describe GetRecordFieldValue, "on a paginated collection field", :resolver do
          attr_accessor :schema_artifacts

          before(:context) do
            self.schema_artifacts = generate_schema_artifacts
          end

          let(:graphql) { build_graphql }

          it "supports forward pagination" do
            response = resolve_nums(11, first: 3)
            expect(response.has_previous_page).to eq false
            expect(response.has_next_page).to eq true
            expect(nodes_of(response)).to eq([1, 2, 3])
            expect(response.nodes).to eq([1, 2, 3])

            response = resolve_nums(11, first: 3, after: response.end_cursor)
            expect(response.has_previous_page).to eq true
            expect(response.has_next_page).to eq true
            expect(nodes_of(response)).to eq([4, 5, 6])
            expect(response.nodes).to eq([4, 5, 6])

            response = resolve_nums(11, first: 8, after: response.end_cursor)
            expect(response.has_previous_page).to eq true
            expect(response.has_next_page).to eq false
            expect(nodes_of(response)).to eq([7, 8, 9, 10, 11])
            expect(response.nodes).to eq([7, 8, 9, 10, 11])
          end

          it "supports backwards pagination" do
            response = resolve_nums(11, last: 3)
            expect(response.has_previous_page).to eq true
            expect(response.has_next_page).to eq false
            expect(nodes_of(response)).to eq([9, 10, 11])
            expect(response.nodes).to eq([9, 10, 11])

            response = resolve_nums(11, last: 3, before: response.start_cursor)
            expect(response.has_previous_page).to eq true
            expect(response.has_next_page).to eq true
            expect(nodes_of(response)).to eq([6, 7, 8])
            expect(response.nodes).to eq([6, 7, 8])

            response = resolve_nums(11, last: 8, before: response.start_cursor)
            expect(response.has_previous_page).to eq false
            expect(response.has_next_page).to eq true
            expect(nodes_of(response)).to eq([1, 2, 3, 4, 5])
            expect(response.nodes).to eq([1, 2, 3, 4, 5])
          end

          it "exposes a unique cursor from each edge" do
            response = resolve_nums(11)
            cursors = response.edges.map(&:cursor)

            expect(cursors).to all match(/\w+/)
            expect(cursors.uniq).to eq cursors
            expect(response.start_cursor).to eq(cursors.first)
            expect(response.end_cursor).to eq(cursors.last)
          end

          it "exposes a `total_edge_count`" do
            response = resolve_nums(11)

            expect(response.total_edge_count).to eq(11)
          end

          it "behaves reasonably when given an empty array" do
            response = resolve_nums(0)

            expect(response.total_edge_count).to eq(0)
            expect(response.page_info.start_cursor).to eq(nil)
            expect(response.page_info.end_cursor).to eq(nil)
            expect(response.has_previous_page).to eq(false)
            expect(response.has_next_page).to eq(false)
            expect(response.edges).to eq([])
            expect(response.nodes).to eq([])
          end

          it "behaves reasonably when given `nil`" do
            response = resolve_nums(nil)

            expect(response.total_edge_count).to eq(0)
            expect(response.page_info.start_cursor).to eq(nil)
            expect(response.page_info.end_cursor).to eq(nil)
            expect(response.has_previous_page).to eq(false)
            expect(response.has_next_page).to eq(false)
            expect(response.edges).to eq([])
            expect(response.nodes).to eq([])
          end

          context "with `max_page_size` configured" do
            let(:graphql) { build_graphql(max_page_size: 10) }

            it "ignores it, allowing the entire array to be returned because we've already paid the cost of fetching the entire array from the datastore, and limiting the page size here doesn't really help us" do
              response = resolve_nums(18)

              expect(nodes_of(response)).to eq([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18])
              expect(response.has_next_page).to eq(false)
              expect(response.has_previous_page).to eq(false)
              expect(response.total_edge_count).to eq(18)
            end
          end

          context "with custom schema element names configured" do
            before(:context) do
              self.schema_artifacts = generate_schema_artifacts(schema_element_name_overrides: {
                "first" => "frst",
                "last" => "lst",
                "before" => "bfr",
                "after" => "aftr"
              })
            end

            it "honors those overrides" do
              response = resolve_nums(11, frst: 3)
              expect(nodes_of(response)).to eq([1, 2, 3])

              response = resolve_nums(11, frst: 3, aftr: response.end_cursor)
              expect(nodes_of(response)).to eq([4, 5, 6])

              response = resolve_nums(11, lst: 3)
              expect(nodes_of(response)).to eq([9, 10, 11])

              response = resolve_nums(11, lst: 3, bfr: response.start_cursor)
              expect(nodes_of(response)).to eq([6, 7, 8])
            end
          end

          def resolve_nums(count, **args)
            natural_numbers = count.is_a?(::Integer) ? 1.upto(count).to_a : count
            resolve("Widget", "natural_numbers", {"natural_numbers" => natural_numbers}, **args)
          end

          def nodes_of(response)
            response.edges.map(&:node)
          end

          def build_graphql(**options)
            super(schema_artifacts: schema_artifacts, **options)
          end

          def generate_schema_artifacts(**options)
            super(**options) do |schema|
              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.paginated_collection_field "natural_numbers", "Int"
                t.index "widgets"
              end
            end
          end
        end
      end
    end
  end
end
