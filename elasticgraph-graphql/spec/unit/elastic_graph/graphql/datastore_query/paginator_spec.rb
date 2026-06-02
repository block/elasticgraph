# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/datastore_query/paginator"
require "elastic_graph/graphql/decoded_cursor"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"

module ElasticGraph
  class GraphQL
    class DatastoreQuery
      RSpec.describe Paginator do
        let(:schema_element_names) { SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: "snake_case") }
        let(:sort_values) { {"id" => "abc123", "created_at" => "2024-01-01T00:00:00Z"} }
        let(:decoded_cursor) { DecodedCursor.new(sort_values) }
        let(:encoded_cursor_string) { decoded_cursor.encode }

        def build_paginator(after: nil, before: nil, first: nil, last: nil)
          Paginator.new(
            default_page_size: 25,
            max_page_size: 100,
            first: first,
            after: after,
            last: last,
            before: before,
            schema_element_names: schema_element_names
          )
        end

        describe "lazy cursor decoding" do
          it "accepts a String for `after` and lazily decodes it in `decoded_after`" do
            paginator = build_paginator(after: encoded_cursor_string)

            expect(paginator.decoded_after).to be_a(DecodedCursor)
            expect(paginator.decoded_after.sort_values).to eq(sort_values)
          end

          it "accepts a String for `before` and lazily decodes it in `decoded_before`" do
            paginator = build_paginator(before: encoded_cursor_string)

            expect(paginator.decoded_before).to be_a(DecodedCursor)
            expect(paginator.decoded_before.sort_values).to eq(sort_values)
          end

          it "returns nil from `decoded_after` when `after` is nil" do
            paginator = build_paginator

            expect(paginator.decoded_after).to be_nil
          end

          it "returns nil from `decoded_before` when `before` is nil" do
            paginator = build_paginator

            expect(paginator.decoded_before).to be_nil
          end

          it "memoizes the decoded cursor to avoid repeated decoding" do
            paginator = build_paginator(after: encoded_cursor_string)

            first_call = paginator.decoded_after
            second_call = paginator.decoded_after

            expect(first_call).to be(second_call)
          end

          it "raises InvalidCursorError when decoding an invalid cursor string" do
            invalid_cursor = "invalid_base64_!@#%"
            paginator = build_paginator(after: invalid_cursor)

            expect {
              paginator.decoded_after
            }.to raise_error(Errors::InvalidCursorError, a_string_including(invalid_cursor))
          end
        end

        describe "#search_after" do
          it "returns the decoded after cursor when not searching in reverse" do
            paginator = build_paginator(first: 10, after: encoded_cursor_string)

            expect(paginator.search_in_reverse?).to be false
            expect(paginator.search_after).to be_a(DecodedCursor)
            expect(paginator.search_after.sort_values).to eq(sort_values)
          end

          it "returns the decoded before cursor when searching in reverse" do
            paginator = build_paginator(last: 10, before: encoded_cursor_string)

            expect(paginator.search_in_reverse?).to be_truthy
            expect(paginator.search_after).to be_a(DecodedCursor)
            expect(paginator.search_after.sort_values).to eq(sort_values)
          end
        end

        describe "#paginated_from_singleton_cursor?" do
          it "returns true when decoded_after is the singleton cursor" do
            singleton_cursor_string = DecodedCursor::SINGLETON.encode
            paginator = build_paginator(after: singleton_cursor_string)

            expect(paginator.paginated_from_singleton_cursor?).to be true
          end

          it "returns true when decoded_before is the singleton cursor" do
            singleton_cursor_string = DecodedCursor::SINGLETON.encode
            paginator = build_paginator(before: singleton_cursor_string)

            expect(paginator.paginated_from_singleton_cursor?).to be true
          end

          it "returns false when neither cursor is the singleton" do
            paginator = build_paginator(after: encoded_cursor_string)

            expect(paginator.paginated_from_singleton_cursor?).to be false
          end

          it "returns false when both cursors are nil" do
            paginator = build_paginator

            expect(paginator.paginated_from_singleton_cursor?).to be false
          end
        end
      end
    end
  end
end
