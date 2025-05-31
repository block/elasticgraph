# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_unit_support"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "highlighting" do
      include_context "DatastoreQueryUnitSupport"

      shared_examples_for "common highlighting examples" do |expected_highlight_fields|
        context "when there are no `client_filters`" do
          it "omits highlights because there are no client filters that could have matches (when there are no `internal_filters`)" do
            query = new_query(
              client_filters: [],
              internal_filters: []
            )

            expect(datastore_body_of(query)).to exclude(:highlight)
          end

          it "omits highlights because there are no client filters that could have matches (when there are `internal_filters`)" do
            query = new_query(
              client_filters: [],
              internal_filters: [{
                "id" => {"equal_to_any_of" => ["123"]}
              }]
            )

            expect(datastore_body_of(query)).to exclude(:highlight)
          end
        end

        context "when there are `client_filters`" do
          it "requests highlights" do
            query = new_query(
              client_filters: [{"name" => {"equal_to_any_of" => ["Bob"]}}]
            )

            expect(datastore_body_of(query)[:highlight]).to include(fields: expected_highlight_fields)
          end

          context "when there are no `internal_filters`" do
            it "omits `highlight_query` because the main search query can safely be used for highlights" do
              query = new_query(
                client_filters: [{"name" => {"equal_to_any_of" => ["Bob"]}}],
                internal_filters: []
              )

              expect(datastore_body_of(query)[:highlight]).to eq(fields: expected_highlight_fields)
            end
          end

          context "when there are also `internal_filters`" do
            it "provides a `highlight_query` based on the `client_filters` so that only client filter matches are highlighted" do
              query = new_query(
                client_filters: [{
                  "name" => {"starts_with" => {"any_prefix_of" => ["Widget"]}},
                  "tags" => {"any_satisfy" => {"contains" => {"any_substring_of" => ["red"]}}}
                }],
                internal_filters: [{
                  "id" => {"equal_to_any_of" => ["123"]}
                }]
              )

              expect(datastore_body_of(query)[:highlight]).to eq({
                fields: expected_highlight_fields,
                highlight_query: {
                  bool: {filter: [
                    {
                      prefix: {"name" => {
                        case_insensitive: false,
                        value: "Widget"
                      }}
                    },
                    {
                      wildcard: {"tags" => {
                        case_insensitive: false,
                        value: "*red*"
                      }}
                    }
                  ]}
                }
              })
            end
          end
        end
      end

      context "with `request_all_highlights: false` and some `requested_highlights`" do
        def new_query(**options)
          super(request_all_highlights: false, requested_highlights: ["name", "options.color"], **options)
        end

        include_examples "common highlighting examples", {"name" => {}, "options.color" => {}}
      end

      context "with `request_all_highlights: true` and `requested_highlights: []`" do
        def new_query(**options)
          super(request_all_highlights: true, requested_highlights: [], **options)
        end

        include_examples "common highlighting examples", {"*" => {}}
      end

      context "with `request_all_highlights: true` and some `requested_highlights`" do
        def new_query(**options)
          super(request_all_highlights: true, requested_highlights: ["name", "options.color"], **options)
        end

        include_examples "common highlighting examples", {"*" => {}}
      end

      context "with `request_all_highlights: false` and `requested_highlights: []`" do
        it "requests no highlights when there are no `client_filters`" do
          query = new_query(request_all_highlights: false, requested_highlights: [], client_filters: [])

          expect(datastore_body_of(query).keys).to exclude(:highlight)
        end

        it "requests no highlights when there are `client_filters`" do
          query = new_query(
            request_all_highlights: false,
            requested_highlights: [],
            client_filters: ["id" => {"equal_to_any_of" => ["123"]}]
          )

          expect(datastore_body_of(query).keys).to exclude(:highlight)
        end
      end
    end
  end
end
