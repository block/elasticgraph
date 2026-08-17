# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  RSpec.describe "Top-level multi-source indexing", :ingests_json_data, :factories, :capture_logs do
    let(:indexer) { build_indexer }

    it "ingests data from multiple source types into a single document, regardless of the ingestion order" do
      options = build(:widget_options, size: "LARGE")
      usd_10 = build(:money, currency: "USD", amount_cents: 10)
      usd_20 = build(:money, currency: "USD", amount_cents: 20)
      widget_v7 = build_upsert_event(:widget, id: "w1", name: "Pre-Thingy", component_ids: ["c23", "c47", "c56"], tags: ["a"], workspace_id: "ws3", options: options, cost: usd_10, __version: 7)
      widget_v8 = build_upsert_event(:widget, id: "w1", name: "Thingy", component_ids: ["c23", "c47", "c56"], tags: ["d", "e", "f"], workspace_id: "ws3", options: options, cost: usd_20, __version: 8)
      old_widget = build_upsert_event(:widget, id: "w1", name: "Old Name", component_ids: ["c23", "c47", "c56"], tags: ["b", "c"], workspace_id: "ws3", options: options, cost: usd_10, __version: 6)

      component1 = build_upsert_event(:component, id: "c23", __version: 1, name: "C", tags: ["a", "b"], part_ids: ["p1"])
      component2 = build_upsert_event(:component, id: "c56", __version: 2, name: "D", tags: ["a", "b"], part_ids: ["p1"])
      component3 = build_upsert_event(:component, id: "c78", __version: 3, name: "E", tags: ["a", "b"], part_ids: ["p1"])

      # ingest component1 before the related widget
      indexer.processor.process([component1], refresh_indices: true)

      # ingest widget after related component1 but before related component2
      indexer.processor.process([widget_v7], refresh_indices: true)

      # ingest an updated widget (with a changed name)
      indexer.processor.process([widget_v8], refresh_indices: true)

      # ingest component2 after related widget, and ingest standalone component3
      indexer.processor.process([component2, component3], refresh_indices: true)

      # ingest an old version of the widget (with a different name); it should be ignored
      indexer.processor.process([old_widget], refresh_indices: true)

      components = search_components

      # The components index should have the 3 we indexed plus the one materialized from the widget reference.
      expect(components.keys).to contain_exactly("c23", "c47", "c56", "c78")

      # This component was indexed before the related widget, and should be fully filled in.
      expect(components["c23"]).to eq({
        "__sources" => ["__self", "widget"],
        "__versions" => {
          "__self" => {"c23" => 1},
          "widget" => {"w1" => 8}
        },
        LIST_COUNTS_FIELD => {
          "tags" => 2,
          "part_ids" => 1,
          "widget_tags" => 3,
          "owner_ids" => 0
        },
        "id" => "c23",
        "name" => "C",
        "part_ids" => ["p1"],
        "tags" => ["a", "b"],
        "widget_name" => "Thingy",
        "widget_workspace_id" => "ws3",
        "widget_size" => "LARGE",
        "widget_tags" => ["d", "e", "f"],
        "widget_cost" => {"currency" => "USD", "amount_cents" => 20}
      })

      # This component was never indexed, but the widget event should have materialized it with `nil` values for all attributes.
      expect(components["c47"]).to eq({
        "__sources" => ["widget"],
        "__versions" => {
          "widget" => {"w1" => 8}
        },
        LIST_COUNTS_FIELD => {
          "widget_tags" => 3
        },
        "id" => "c47",
        "name" => nil,
        "part_ids" => nil,
        "tags" => nil,
        "widget_name" => "Thingy",
        "widget_workspace_id" => "ws3",
        "widget_size" => "LARGE",
        "widget_tags" => ["d", "e", "f"],
        "widget_cost" => {"currency" => "USD", "amount_cents" => 20}
      })

      # This component was indexed after the related widget, and should be fully filled in.
      expect(components["c56"]).to eq({
        "__sources" => ["__self", "widget"],
        "__versions" => {
          "__self" => {"c56" => 2},
          "widget" => {"w1" => 8}
        },
        LIST_COUNTS_FIELD => {
          "part_ids" => 1,
          "tags" => 2,
          "widget_tags" => 3,
          "owner_ids" => 0
        },
        "id" => "c56",
        "name" => "D",
        "part_ids" => ["p1"],
        "tags" => ["a", "b"],
        "widget_name" => "Thingy",
        "widget_workspace_id" => "ws3",
        "widget_size" => "LARGE",
        "widget_tags" => ["d", "e", "f"],
        "widget_cost" => {"currency" => "USD", "amount_cents" => 20}
      })

      # The related widget for this component was never indexed, so it's missing the widget data.
      expect(components["c78"]).to eq({
        "__sources" => ["__self"],
        "__versions" => {
          "__self" => {"c78" => 3}
        },
        LIST_COUNTS_FIELD => {
          "part_ids" => 1,
          "tags" => 2,
          "owner_ids" => 0
        },
        "id" => "c78",
        "name" => "E",
        "part_ids" => ["p1"],
        "tags" => ["a", "b"],
        "widget_name" => nil,
        "widget_workspace_id" => nil,
        "widget_size" => nil,
        "widget_tags" => nil,
        "widget_cost" => nil
      })
    end

    it "does not allow mutations of relationships used by `sourced_from`, since allowing such a mutation would break ElasticGraph's 'ingest in any order' guarantees" do
      widget1 = build_upsert_event(:widget, id: "w1", component_ids: ["c23"])
      widget2 = build_upsert_event(:widget, id: "w2", component_ids: ["c23"])

      indexer.processor.process([widget1], refresh_indices: true)

      expect {
        indexer.processor.process([widget2], refresh_indices: true)
      }.to raise_error Indexer::IndexingFailuresError, a_string_including(
        "Cannot update document c23 with data from related widget w2 because the related widget has apparently changed (was: [w1]), " \
        "but mutations of relationships used with `sourced_from` are not supported because allowing it could break ElasticGraph's " \
        "out-of-order processing guarantees."
      )
    end

    it "fills in a top-level sourced field from a pure-source (non-indexed) type, regardless of ingestion order" do
      design1 = build_upsert_event(:component_design, id: "d1", component_id: "c1", designer_name: "Alice", __version: 1)
      design2 = build_upsert_event(:component_design, id: "d2", component_id: "c2", designer_name: "Bob", __version: 1)
      component1 = build_upsert_event(:component, id: "c1", name: "C1", __version: 1)
      component2 = build_upsert_event(:component, id: "c2", name: "C2", __version: 1)

      # `design1` arrives BEFORE its component exists, materializing an incomplete document containing
      # just the identity, bookkeeping, and the sourced field.
      indexer.processor.process([design1], refresh_indices: true)

      expect(component_source("c1")).to eq(
        "id" => "c1",
        "__counts" => {},
        "__sources" => ["design"],
        "__versions" => {"design" => {"d1" => 1}},
        "designer_name" => "Alice"
      )

      indexer.processor.process([component1, component2], refresh_indices: true)

      # `design2` arrives AFTER its component was indexed.
      indexer.processor.process([design2], refresh_indices: true)

      component1_source = component_source("c1")
      expect(component1_source).to include("id" => "c1", "name" => "C1", "designer_name" => "Alice")
      expect(component1_source.fetch("__sources")).to contain_exactly("__self", "design")
      # Top-level sourced fields record their versions under the bare relationship name (nested ones
      # use element-qualified keys), and involve none of the nested bookkeeping.
      expect(component1_source.fetch("__versions")).to eq("__self" => {"c1" => 1}, "design" => {"d1" => 1})
      expect(component1_source).not_to have_key("__nested_sourced_data")

      component2_source = component_source("c2")
      expect(component2_source).to include("id" => "c2", "name" => "C2", "designer_name" => "Bob")
      expect(component2_source.fetch("__sources")).to contain_exactly("__self", "design")
      expect(component2_source.fetch("__versions")).to eq("__self" => {"c2" => 1}, "design" => {"d2" => 1})

      # `ComponentDesign` is pure-source (non-indexed), so its events update component documents only--
      # no standalone design documents get written.
      design_hits = main_datastore_client
        .msearch(body: [{index: "component_designs*"}, {query: {match_all: {}}}])
        .dig("responses", 0, "hits", "hits")
      expect(design_hits).to eq []
    end

    it "is compatible with custom shard routing and rollover indices, so long as `equivalent_field` is used on the schema definition" do
      # Use timestamps with explicit 3-digit millisecond precision to match what the indexer normalizes to
      timestamp_in_2023 = "2023-08-09T10:12:14.000Z"
      timestamp_in_2021 = "2021-08-09T10:12:14.000Z"

      widget = build_upsert_event(:widget, id: "w1", workspace_id: "wid_23", created_at: timestamp_in_2023)
      workspace = build_upsert_event(:widget_workspace, id: "wid_23", name: "Garage", created_at: timestamp_in_2021, widget: {
        id: "w1",
        created_at: timestamp_in_2023
      })

      indexer.processor.process([widget, workspace], refresh_indices: true)

      indexed_widget_source = search("widgets").dig(0, "_source")
      expect(indexed_widget_source).to include({
        "id" => "w1",
        "created_at" => timestamp_in_2023,
        "workspace_id2" => "wid_23",
        "workspace_name" => "Garage" # the sourced_from field copied from the `WidgetWorkspace`
      })
    end

    def component_source(id)
      main_datastore_client
        .msearch(body: [{index: "components*"}, {query: {ids: {values: [id]}}}])
        .dig("responses", 0, "hits", "hits", 0, "_source")
    end

    def search_components
      search("components").to_h do |hit|
        source = hit.fetch("_source")

        [
          hit.fetch("_id"),
          {
            "id" => source.fetch("id"),
            "name" => source.dig("name"),
            "part_ids" => source.dig("part_ids"),
            "tags" => source.dig("tags"),
            "widget_cost" => source.dig("widget_cost"),
            "widget_name" => source.dig("widget_name"),
            "widget_size" => source.dig("widget_size"),
            "widget_tags" => source.dig("widget_tags"),
            "widget_workspace_id" => source.dig("widget_workspace_id3"),
            "__versions" => source.dig("__versions"),
            "__sources" => source.dig("__sources"),
            LIST_COUNTS_FIELD => source.dig(LIST_COUNTS_FIELD)
          }
        ]
      end
    end

    def search(index_prefix)
      main_datastore_client
        .msearch(body: [{index: "#{index_prefix}*"}, {}])
        .dig("responses", 0, "hits", "hits")
    end
  end
end
