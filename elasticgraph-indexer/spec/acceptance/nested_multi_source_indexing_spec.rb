# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  # Exercises nested `sourced_from`: `career_wins` sourced onto elements embedded within a `Team` rather than
  # onto the root, covering both path shapes the painless script navigates: `staff.coaches` (matched by id) and
  # `staff.general_manager` (the all-object path, reached by field name).
  RSpec.describe "Nested multi-source indexing", :uses_datastore, :factories, :capture_logs do
    let(:indexer) { build_indexer }

    # Multi-byte to verify the length-prefixed element-key encoding (UTF-16 code units) round-trips.
    let(:multibyte_coach_id) { "coach-bjørn" }

    it "fills in nested sourced fields on embedded list elements and singleton objects, regardless of ingestion order" do
      league = "NBA"
      formed_on = "2019-04-23"

      team = build_upsert_event(
        :team,
        id: "t1",
        league: league,
        formed_on: formed_on,
        staff: build(
          :staff,
          coaches: [
            build(:coach, id: "c1", name: "Alice"),
            build(:coach, id: multibyte_coach_id, name: "Bjørn")
          ],
          general_manager: build(:general_manager, id: "gm1", name: "Casey")
        )
      )

      record_for = ->(coach_id, wins) do
        build_upsert_event(
          :coach_record,
          id: "rec-#{coach_id}",
          team_id: "t1",
          coach_id: coach_id,
          wins: wins,
          team_league: league,
          team_formed_on: formed_on
        )
      end

      record_c1 = record_for.call("c1", 100)
      record_c2 = record_for.call(multibyte_coach_id, 200)
      # The GM feed is a distinct source type, matched purely by `team_id`.
      record_gm = build_upsert_event(
        :general_manager_record,
        id: "rec-gm1",
        team_id: "t1",
        wins: 300,
        team_league: league,
        team_formed_on: formed_on
      )

      # `record_c1` arrives BEFORE the team exists (out-of-order buffer path); the rest arrive after.
      indexer.processor.process([record_c1], refresh_indices: true)
      indexer.processor.process([team], refresh_indices: true)
      indexer.processor.process([record_c2, record_gm], refresh_indices: true)

      source = indexed_team_source("t1")

      expect(source["id"]).to eq("t1")

      staff = source.fetch("staff")
      coaches_by_id = staff.fetch("coaches").to_h { |c| [c.fetch("id"), c] }
      expect(coaches_by_id.keys).to contain_exactly("c1", multibyte_coach_id)

      expect(coaches_by_id.fetch("c1")).to include("name" => "Alice", "career_wins" => 100)
      expect(coaches_by_id.fetch(multibyte_coach_id)).to include("name" => "Bjørn", "career_wins" => 200)
      expect(staff.fetch("general_manager")).to include("name" => "Casey", "career_wins" => 300)

      # `__sources`/`__versions` are keyed by the qualified nested relationship. Each nested element gets its own
      # `__versions` bucket so sibling coaches don't collide; nested keys encode one `len:value|` part per path
      # segment (object segment → field name, list segment → matched `coach_id`).
      expect(source.fetch("__sources")).to contain_exactly("__self", "staff.coaches.record", "staff.general_manager.record")

      expect(source.fetch("__versions")).to eq(
        "__self" => {"t1" => version_of(team)},
        "20:staff.coaches.record|5:staff|2:c1|" => {"rec-c1" => version_of(record_c1)},
        "20:staff.coaches.record|5:staff|11:coach-bjørn|" => {"rec-#{multibyte_coach_id}" => version_of(record_c2)},
        "28:staff.general_manager.record|5:staff|15:general_manager|" => {"rec-gm1" => version_of(record_gm)}
      )
    end

    def version_of(event)
      event.fetch("version")
    end

    def indexed_team_source(id)
      main_datastore_client
        .msearch(body: [{index: "teams*"}, {query: {ids: {values: [id]}}}])
        .dig("responses", 0, "hits", "hits", 0, "_source")
    end
  end
end
