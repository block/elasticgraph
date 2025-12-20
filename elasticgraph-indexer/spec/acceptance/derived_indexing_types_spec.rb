# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  RSpec.describe "A derived indexing type", :uses_datastore, :factories, :capture_logs do
    let(:indexer) { build_indexer }

    it "maintains derived fields, handling nested source and destination fields as needed" do
      # Index only 1 record initially, so we can verify the state of the document when it is
      # first inserted. This is important because the metadata available to `ctx` in our script
      # is a bit different for an update to an existing document vs the insertion of a new one.
      # Previously, we had a bug that was hidden because we didn't verify JUST the result of
      # processing one source document.
      #
      # We use specific created_at timestamps with different millisecond precision to verify
      # that DateTime normalization works correctly for min value tracking. Without normalization,
      # string comparison of ".531Z" vs ".53Z" would incorrectly pick .531Z as the minimum
      # because 'Z' (ASCII 90) > '1' (ASCII 49).
      w1_created_at = "2023-11-01T10:30:00.531Z"  # 531 milliseconds
      w1 = index_records(widget("LARGE", "RED", "USD", name: "foo1", tags: ["b1", "c2", "a3"], fee_currencies: ["CAD", "GBP"], created_at: w1_created_at)).first

      expect_payload_from_lookup_and_search({
        "id" => "USD",
        "name" => "United States Dollar",
        "details" => {"symbol" => "$", "unit" => "dollars"},
        "widget_names2" => ["foo1"],
        "widget_tags" => ["a3", "b1", "c2"],
        "widget_fee_currencies" => ["CAD", "GBP"],
        "widget_options" => {
          "colors" => ["RED"],
          "sizes" => ["LARGE"]
        },
        "nested_fields" => {
          "max_widget_cost" => w1.fetch("record").fetch("cost").fetch("amount_cents")
        },
        "oldest_widget_created_at" => "2023-11-01T10:30:00.531Z"
      })

      # Now index a lot more documents so we can verify that we maintain a sorted list of unique values.
      # Include a widget with 2-digit milliseconds (.53Z = 530ms) that is earlier than w1 (.531Z = 531ms).
      # Without DateTime normalization, string comparison would incorrectly select .531Z as the minimum.
      oldest_created_at = "2023-11-01T10:30:00.53Z"  # 530 milliseconds - the oldest
      widgets = index_records(
        widget("SMALL", "RED", "USD", name: "bar1", tags: ["d4", "d4", "e5"], created_at: oldest_created_at),
        widget("LARGE", "RED", "USD", name: "foo1", tags: [], fee_currencies: ["CAD", "USD"], created_at: "2023-11-02T10:30:00.000Z"),
        widget("SMALL", "BLUE", "CAD", name: "bazz", tags: ["a6"]),
        widget("LARGE", "BLUE", "USD", name: "bar2", tags: ["a6", "a5"], created_at: "2023-11-03T10:30:00.000Z"),
        widget("SMALL", "BLUE", "USD", name: "foo1", tags: [], created_at: "2023-11-04T10:30:00.000Z"),
        widget("LARGE", "BLUE", "USD", name: "foo2", tags: [], created_at: "2023-11-05T10:30:00.000Z"),
        widget(nil, nil, "USD", name: nil, tags: [], created_at: "2023-11-06T10:30:00.000Z"), # nils scalars should be ignored.
        widget(nil, nil, "USD", name: nil, options: nil, tags: [], created_at: "2023-11-07T10:30:00.000Z"), # ...as should nil parent objects
        widget("MEDIUM", "GREEN", nil, name: "foo3", tags: ["z12"]), # ...as should events with `nil` for the derived indexing type id
        widget("MEDIUM", "GREEN", "", name: "foo3", tags: ["z12"]), # ...as should events with empty string for the derived indexing type id
        widget("SMALL", "RED", "USD", name: "", tags: ["g8"], created_at: "2023-11-08T10:30:00.000Z") # but empty string values can be put in the set. It's odd but seems more correct then not allowing it.
      )

      expect_payload_from_lookup_and_search({
        "id" => "USD",
        "name" => "United States Dollar",
        "details" => {"symbol" => "$", "unit" => "dollars"},
        "widget_names2" => ["", "bar1", "bar2", "foo1", "foo2"],
        "widget_tags" => ["a3", "a5", "a6", "b1", "c2", "d4", "e5", "g8"],
        "widget_fee_currencies" => ["CAD", "GBP", "USD"],
        "widget_options" => {
          "colors" => ["BLUE", "RED"],
          "sizes" => ["LARGE", "SMALL"]
        },
        "nested_fields" => {
          "max_widget_cost" => ([w1] + widgets).select { |w| w.dig("record", "cost", "currency") == "USD" }.map { |w| w.fetch("record").fetch("cost").fetch("amount_cents") }.max
        },
        # Without DateTime normalization, this would incorrectly be "2023-11-01T10:30:00.531Z"
        # because ".53Z" > ".531Z" in string comparison ('Z' > '1').
        # With normalization, ".53Z" becomes ".530Z" and correctly compares as less than ".531Z".
        "oldest_widget_created_at" => "2023-11-01T10:30:00.530Z"
      })
    end

    it "creates the derived document with empty field values when indexing a source document that lacks field values" do
      w1_created_at = "2023-11-15T10:30:00.123Z"
      w1 = widget(nil, nil, "GBP", name: nil, tags: [], cost_currency_name: nil, cost_currency_symbol: nil, cost_currency_unit: "dollars", created_at: w1_created_at)
      w1[:cost][:amount_cents] = nil

      index_records(w1)

      expect_payload_from_lookup_and_search({
        "id" => "GBP",
        "name" => nil,
        "details" => {"symbol" => nil, "unit" => "dollars"},
        "widget_names2" => [],
        "widget_tags" => [],
        "widget_fee_currencies" => [],
        "widget_options" => {
          "colors" => [],
          "sizes" => []
        },
        "nested_fields" => {
          "max_widget_cost" => nil
        },
        "oldest_widget_created_at" => "2023-11-15T10:30:00.123Z"
      })
    end

    it "logs the noop result when a DerivedIndexUpdate operation results in no state change in the datastore" do
      w1_created_at = "2023-11-20T10:30:00.456Z"
      w1 = widget(nil, nil, "GBP", name: "widget1", tags: [], created_at: w1_created_at)
      index_records(w1)

      expect { index_records(w1) }.to change { logged_output }.from(a_string_excluding("noop")).to(a_string_including("noop"))

      expect_payload_from_lookup_and_search({
        "id" => "GBP",
        "name" => "British Pound Sterling",
        "details" => {"symbol" => "£", "unit" => "pounds"},
        "widget_names2" => ["widget1"],
        "widget_tags" => [],
        "widget_fee_currencies" => [],
        "widget_options" => {
          "colors" => [],
          "sizes" => []
        },
        "nested_fields" => {
          "max_widget_cost" => w1.fetch(:cost).fetch(:amount_cents)
        },
        "oldest_widget_created_at" => "2023-11-20T10:30:00.456Z"
      })
    end

    describe "`immutable_value` fields" do
      it "does not allow it change value" do
        index_records(
          widget("LARGE", "RED", "USD", cost_currency_name: "United States Dollar", cost_currency_unit: "dollars", cost_currency_symbol: "$")
        )

        expect_payload_from_lookup_and_search({
          "id" => "USD",
          "name" => "United States Dollar",
          "details" => {"unit" => "dollars", "symbol" => "$"}
        })

        expect {
          index_records(
            widget("LARGE", "RED", "USD", cost_currency_name: "US Dollar", cost_currency_unit: "dollar", cost_currency_symbol: "US$")
          )
        }.to raise_error(Indexer::IndexingFailuresError, a_string_including(
          "Field `name` cannot be changed (United States Dollar => US Dollar).",
          "Field `details.unit` cannot be changed (dollars => dollar).",
          "Field `details.symbol` cannot be changed ($ => US$)."
        ))

        expect_payload_from_lookup_and_search({
          "id" => "USD",
          "name" => "United States Dollar",
          "details" => {"unit" => "dollars", "symbol" => "$"}
        })
      end

      it "ignores an event that tries to change the value if that event has already been superseded by a corrected event with a greater version" do
        # Original widget.
        widget_v1 = widget("LARGE", "RED", "USD", cost_currency_symbol: "$", id: "w1", workspace_id: "wid23")

        # Updated widget, which wrongly tries to change the currency symbol of USD.
        widget_v2 = widget("LARGE", "RED", "USD", cost_currency_symbol: "US$", id: "w1", workspace_id: "wid23", __version: widget_v1.fetch(:__version) + 1)
        widget_v2_event_id = Indexer::EventID.from_event(Indexer::TestSupport::Converters.upsert_events_for_records([widget_v2]).first).to_s

        # Later updated widget, which does not try to change the currency symbol.
        widget_v3 = widget("LARGE", "RED", "USD", cost_currency_symbol: "$", id: "w1", workspace_id: "wid23", __version: widget_v1.fetch(:__version) + 2, name: "3rd version")

        index_records(widget_v1)

        # When our widget with a changed currency symbol is processed, we should get an error since changing it is not allowed.
        expect {
          index_records(widget_v2)
        }.to raise_error(
          Indexer::IndexingFailuresError,
          a_string_including("Field `details.symbol` cannot be changed ($ => US$).", widget_v2_event_id)
        )

        index_records(widget_v3)

        # ...but if we retry after the event has been superseded by a corrected event, it just logs a warning instead.
        expect {
          index_records(widget_v2)
        }.to log_warning(a_string_including("superseded by corrected events", widget_v2_event_id))
      end

      it "allows it to be set to `null` unless `nullable: false` was passed on the definition" do
        expect {
          index_records(
            # The `unit` derivation was defined with `nullable: false`.
            widget("LARGE", "RED", "USD", cost_currency_name: "United States Dollar", cost_currency_unit: nil)
          )
        }.to raise_error(Indexer::IndexingFailuresError, a_string_including("#{DERIVED_INDEX_FAILURE_MESSAGE_PREAMBLE}: Field `details.unit` cannot be set to `null`, but the source event contains no value for it. Remove `nullable: false` from the `immutable_value` definition to allow this."))

        expect(fetch_from_index("WidgetCurrency", "USD")).to eq nil

        index_records(
          # ...but the `name` derivation does not have `nullable: false`.
          widget("LARGE", "RED", "USD", cost_currency_name: nil, cost_currency_unit: "dollars")
        )

        expect_payload_from_lookup_and_search({
          "id" => "USD",
          "name" => nil,
          "details" => {"unit" => "dollars", "symbol" => "$"}
        })
      end

      it "allows a one-time change from `null` to a non-null value if `can_change_from_null: true` was passed on the definition" do
        # When an immutable value defined with `can_change_from_null: true` is initially indexed as `null`....
        index_records(widget("LARGE", "RED", "USD", cost_currency_symbol: nil))
        expect_payload_from_lookup_and_search({"id" => "USD", "details" => {"unit" => "dollars", "symbol" => nil}})

        # ...we allow it to change to a non-null value once...
        index_records(widget("LARGE", "RED", "USD", cost_currency_symbol: "$"))
        expect_payload_from_lookup_and_search({"id" => "USD", "details" => {"unit" => "dollars", "symbol" => "$"}})

        # ...and ignore any attempts to change it back to null.
        index_records(widget("LARGE", "RED", "USD", cost_currency_symbol: nil))
        expect_payload_from_lookup_and_search({"id" => "USD", "details" => {"unit" => "dollars", "symbol" => "$"}})

        # ...and don't allow it to be changed to another value.
        expect {
          index_records(widget("LARGE", "RED", "USD", cost_currency_symbol: "US$"))
        }.to raise_error(Indexer::IndexingFailuresError, a_string_including(
          "Field `details.symbol` cannot be changed ($ => US$)."
        ))
        expect_payload_from_lookup_and_search({"id" => "USD", "details" => {"unit" => "dollars", "symbol" => "$"}})
      end

      it "does not allow nullable fields to change from null if `can_change_from_null: true` wasn't passed on the definition" do
        index_records(widget("LARGE", "RED", "USD", cost_currency_name: nil))
        expect_payload_from_lookup_and_search({"id" => "USD", "name" => nil})

        expect {
          index_records(widget("LARGE", "RED", "USD", cost_currency_name: "US Dollar"))
        }.to raise_error(Indexer::IndexingFailuresError, a_string_including(
          "Field `name` cannot be changed (null => US Dollar).",
          "Set `can_change_from_null: true` on the `immutable_value` definition to allow this."
        ))
        expect_payload_from_lookup_and_search({"id" => "USD", "name" => nil})
      end
    end

    it "derives a max `JsonSafeLong` when an integer-range value is indexed before a long-range value" do
      small = widget("SMALL", "RED", "USD", name: "small_weight", tags: [], weight_in_ng: 1_000)
      large = widget("LARGE", "RED", "USD", name: "large_weight", tags: [], weight_in_ng: large_value = 99_000_000_000_000)

      index_records(small)
      index_records(large)

      doc = fetch_from_index("WidgetCurrency", "USD")
      expect(doc.dig("max_weight_in_ng")).to eq(large_value)
    end

    it "derives a max `JsonSafeLong` when an long-range value is indexed before an integer-range value" do
      small = widget("SMALL", "RED", "USD", name: "small_weight", tags: [], weight_in_ng: 1_000)
      large = widget("LARGE", "RED", "USD", name: "large_weight", tags: [], weight_in_ng: large_value = 99_000_000_000_000)

      index_records(large)
      index_records(small)

      doc = fetch_from_index("WidgetCurrency", "USD")
      expect(doc.dig("max_weight_in_ng")).to eq(large_value)
    end

    it "handles numeric min/max when source values are Integers" do
      large_value = 200_000_000
      small = widget("SMALL", "RED", "USD", name: "small_cost", tags: [], cost: {amount_cents: 100, currency: "USD"})
      large = widget("LARGE", "RED", "USD", name: "large_cost", tags: [], cost: {amount_cents: large_value, currency: "USD"})

      index_records(small, large)

      doc = fetch_from_index("WidgetCurrency", "USD")
      expect(doc.dig("nested_fields", "max_widget_cost")).to eq(large_value)
    end

    def expect_payload_from_lookup_and_search(payload)
      doc = fetch_from_index("WidgetCurrency", payload.fetch("id"))
      expect(doc).to include(payload)

      search_response = search_by_type_and_id("WidgetCurrency", [payload.fetch("id")])
      expect(search_response.size).to eq(1)
      expect(search_response.first.fetch("_source")).to include(payload)
    end

    def widget(size, color, currency, fee_currencies: [], **widget_attributes)
      widget_attributes = {
        options: build(:widget_options, color: color, size: size),
        cost: (build(:money, currency: currency) if currency),
        fees: fee_currencies.map { |c| build(:money, currency: c) }
      }.merge(widget_attributes)

      build(:widget, **widget_attributes)
    end

    def fetch_from_index(type, id)
      currency = ElasticGraphSpecSupport::CURRENCIES_BY_CODE.fetch(id)
      index_name = indexer.datastore_core.index_definitions_by_graphql_type.fetch(type).first
        .index_name_for_writes({"introduced_on" => currency.fetch(:introduced_on)})

      result = search_index_by_id(index_name, [id])
      result.first&.fetch("_source")
    end

    def search_by_type_and_id(type, ids)
      index_name = indexer.datastore_core.index_definitions_by_graphql_type.fetch(type).first.index_expression_for_search
      search_index_by_id(index_name, ids)
    end

    def search_index_by_id(index_name, ids, **metadata)
      main_datastore_client.msearch(body: [{index: index_name, **metadata}, {
        query: {bool: {filter: [{terms: {id: ids}}]}}
      }]).dig("responses", 0, "hits", "hits")
    end
  end
end
