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
    let(:league) { "NBA" }
    let(:formed_on) { "2019-04-23" }

    # Multi-byte to verify the length-prefixed element-key encoding (UTF-16 code units) round-trips.
    let(:multibyte_coach_id) { "coach-bjørn" }

    it "fills in nested sourced fields on embedded list elements and singleton objects, regardless of ingestion order" do
      # Pin distinct explicit versions per record so the `__versions` assertion below is both deterministic
      # (the factory otherwise auto-increments based on how many records were built first) and unambiguous --
      # each bucket's value pins it to a specific source event, catching any cross-element mixup.
      team = team_event(version: 10)
      record_c1 = coach_record_for("c1", 100, version: 11)
      record_c2 = coach_record_for(multibyte_coach_id, 200, version: 12)
      record_gm = gm_record(300, version: 13)

      # `record_c1` arrives BEFORE the team exists (out-of-order buffer path); the rest arrive after.
      indexer.processor.process([record_c1], refresh_indices: true)
      indexer.processor.process([team], refresh_indices: true)
      indexer.processor.process([record_c2, record_gm], refresh_indices: true)

      source = indexed_team_source("t1")

      expect(source["id"]).to eq("t1")

      coaches_by_id = coaches_by_id_from(source)
      expect(coaches_by_id.keys).to contain_exactly("c1", multibyte_coach_id)

      expect(coaches_by_id.fetch("c1")).to include("name" => "Alice", "career_wins" => 100)
      expect(coaches_by_id.fetch(multibyte_coach_id)).to include("name" => "Bjørn", "career_wins" => 200)
      expect(source.fetch("staff").fetch("general_manager")).to include("name" => "Casey", "career_wins" => 300)

      # `__sources`/`__versions` are keyed by the qualified nested relationship. Each nested element gets its own
      # `__versions` bucket so sibling coaches don't collide; nested keys encode one `len:value|` part per path
      # segment (object segment → field name, list segment → matched `coach_id`).
      expect(source.fetch("__sources")).to contain_exactly("__self", "staff.coaches.record", "staff.general_manager.record")

      expect(source.fetch("__versions")).to eq(
        "__self" => {"t1" => 10},
        "20:staff.coaches.record|5:staff|2:c1|" => {"rec-c1" => 11},
        "20:staff.coaches.record|5:staff|11:coach-bjørn|" => {"rec-#{multibyte_coach_id}" => 12},
        "28:staff.general_manager.record|5:staff|15:general_manager|" => {"rec-gm1" => 13}
      )
    end

    it "preserves already-sourced nested fields when the root document is re-indexed" do
      # Source `career_wins` onto `c1`, then re-index the team. The new team event re-sends the `staff.coaches`
      # array WITHOUT `career_wins` (a publisher doesn't know about sourced fields), overwriting the nested array;
      # the script must re-apply the buffered sourced data so it survives the root update.
      indexer.processor.process([coach_record_for("c1", 100)], refresh_indices: true)
      indexer.processor.process([team_event(version: 1)], refresh_indices: true)

      expect(coaches_by_id_from(indexed_team_source("t1")).fetch("c1")).to include("career_wins" => 100)

      indexer.processor.process([team_event(version: 2)], refresh_indices: true)

      expect(coaches_by_id_from(indexed_team_source("t1")).fetch("c1")).to include("name" => "Alice", "career_wins" => 100)
    end

    it "ignores a stale (lower-version) source event for an already-sourced nested element" do
      indexer.processor.process([team_event], refresh_indices: true)
      indexer.processor.process([coach_record_for("c1", 200, version: 5)], refresh_indices: true)

      # An older version of the same coach's record must not overwrite the newer sourced value.
      indexer.processor.process([coach_record_for("c1", 100, version: 2)], refresh_indices: true)

      expect(coaches_by_id_from(indexed_team_source("t1")).fetch("c1")).to include("career_wins" => 200)
    end

    it "rejects a mutation of the relationship used by a nested `sourced_from` field" do
      indexer.processor.process([team_event], refresh_indices: true)
      indexer.processor.process([coach_record_for("c1", 100, id: "rec-a")], refresh_indices: true)

      # A second record (different source id) targeting the same coach is treated as a relationship mutation,
      # which would break out-of-order processing guarantees, so it is rejected.
      expect {
        indexer.processor.process([coach_record_for("c1", 200, id: "rec-b")], refresh_indices: true)
      }.to raise_error Indexer::IndexingFailuresError, a_string_including(
        "apparently changed", "mutations of relationships used with `sourced_from` are not supported"
      )
    end

    def team_event(version: nil)
      build_upsert_event(
        :team,
        **(version ? {__version: version} : {}),
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
    end

    def coach_record_for(coach_id, wins, id: "rec-#{coach_id}", version: nil)
      build_upsert_event(
        :coach_record,
        **(version ? {__version: version} : {}),
        id: id,
        team_id: "t1",
        coach_id: coach_id,
        wins: wins,
        team_league: league,
        team_formed_on: formed_on
      )
    end

    # The GM feed is a distinct source type, matched purely by `team_id`.
    def gm_record(wins, version: nil)
      build_upsert_event(
        :general_manager_record,
        **(version ? {__version: version} : {}),
        id: "rec-gm1",
        team_id: "t1",
        wins: wins,
        team_league: league,
        team_formed_on: formed_on
      )
    end

    def coaches_by_id_from(source)
      source.fetch("staff").fetch("coaches").to_h { |c| [c.fetch("id"), c] }
    end

    def indexed_team_source(id)
      main_datastore_client
        .msearch(body: [{index: "teams*"}, {query: {ids: {values: [id]}}}])
        .dig("responses", 0, "hits", "hits", 0, "_source")
    end
  end
end
