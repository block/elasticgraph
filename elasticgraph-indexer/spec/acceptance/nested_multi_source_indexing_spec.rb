# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  RSpec.describe "Nested multi-source indexing", :ingests_json_data, :factories, :capture_logs do
    let(:indexer) { build_indexer }
    let(:league) { "NBA" }
    let(:formed_on) { "2019-04-23" }

    it "fills in nested sourced fields on embedded list elements and singleton objects, regardless of ingestion order" do
      team = team_event(version: 10)
      coach_profile_1 = coach_profile_event("c1", 100, version: 11)
      # `cø` is 2 UTF-16 code units but 3 UTF-8 bytes, so the `2:cø|` key part below confirms the element-key
      # prefix counts code units (what painless `String.length()` returns), not bytes.
      coach_profile_2 = coach_profile_event("cø", 200, version: 12)
      gm_profile = gm_profile_event(300, version: 13)

      # `coach_profile_1` arrives BEFORE the team exists (out-of-order buffer path); the rest arrive after.
      indexer.processor.process([coach_profile_1], refresh_indices: true)
      indexer.processor.process([team], refresh_indices: true)
      indexer.processor.process([coach_profile_2, gm_profile], refresh_indices: true)

      source = fetch_team_source("t1")

      expect(source["id"]).to eq("t1")

      coaches_by_id = coaches_by_id_in(source)
      expect(coaches_by_id.keys).to contain_exactly("c1", "cø")

      expect(coaches_by_id.fetch("c1")).to eq("id" => "c1", "name" => "Alice", "salary" => 100)
      expect(coaches_by_id.fetch("cø")).to eq("id" => "cø", "name" => "Bob", "salary" => 200)
      expect(source.fetch("staff").fetch("general_manager")).to eq("id" => "gm1", "name" => "Casey", "salary" => 300)

      # Each nested element gets its own `__versions` bucket, keyed by the qualified relationship followed by one
      # `len:value|` part per path segment, so sibling coaches don't collide; `__sources` keeps the bare
      # qualified relationship. These keys are hardcoded (not computed) so the test pins the exact script output.
      expect(source.fetch("__sources")).to contain_exactly("__self", "staff.coaches.profile", "staff.general_manager.profile")

      # `staff` shows up twice per key because the halves are independent: the qualified relationship (kept verbatim
      # for the script's nested-paths lookup), then one identifier part per path segment--an object segment
      # contributes its field name since it has no per-element id.
      expect(source.fetch("__versions")).to eq(
        "__self" => {"t1" => 10},
        "21:staff.coaches.profile|5:staff|2:c1|" => {"prof-c1" => 11},
        "21:staff.coaches.profile|5:staff|2:cø|" => {"prof-cø" => 12},
        "29:staff.general_manager.profile|5:staff|15:general_manager|" => {"prof-gm1" => 13}
      )
    end

    it "preserves already-sourced nested fields when the root document is re-indexed" do
      indexer.processor.process([coach_profile_event("c1", 100)], refresh_indices: true)
      indexer.processor.process([team_event(version: 1)], refresh_indices: true)

      expect(coaches_by_id_in(fetch_team_source("t1")).fetch("c1")).to eq("id" => "c1", "name" => "Alice", "salary" => 100)

      # The re-indexed team re-sends `staff.coaches` without `salary` (publishers don't know about sourced
      # fields), overwriting the nested array; the buffered sourced data must be re-applied so it survives.
      indexer.processor.process([team_event(version: 2)], refresh_indices: true)

      source = fetch_team_source("t1")
      coaches_by_id = coaches_by_id_in(source)
      expect(coaches_by_id.fetch("c1")).to eq("id" => "c1", "name" => "Alice", "salary" => 100)
      # The sibling coach and the GM are never sourced, so `salary` is absent (not nil) and the re-index
      # leaves them untouched.
      expect(coaches_by_id.fetch("cø")).to eq("id" => "cø", "name" => "Bob")
      expect(source.fetch("staff").fetch("general_manager")).to eq("id" => "gm1", "name" => "Casey")
    end

    it "ignores a stale (lower-version) source event for an already-sourced nested element" do
      indexer.processor.process([team_event], refresh_indices: true)
      indexer.processor.process([coach_profile_event("c1", 200, version: 5)], refresh_indices: true)
      indexer.processor.process([coach_profile_event("c1", 100, version: 2)], refresh_indices: true)

      source = fetch_team_source("t1")
      coaches_by_id = coaches_by_id_in(source)
      expect(coaches_by_id.fetch("c1")).to eq("id" => "c1", "name" => "Alice", "salary" => 200)
      # The sibling coach was never sourced, so `salary` is absent and applying c1's events leaves it alone.
      expect(coaches_by_id.fetch("cø")).to eq("id" => "cø", "name" => "Bob")
      # The recorded version stays at the newer event's, not the stale one's.
      expect(source.fetch("__versions").fetch("21:staff.coaches.profile|5:staff|2:c1|")).to eq("prof-c1" => 5)
    end

    it "clears an already-sourced nested field when a newer source event drops the value upstream" do
      indexer.processor.process([team_event], refresh_indices: true)
      indexer.processor.process([coach_profile_event("c1", 100, version: 1)], refresh_indices: true)

      expect(coaches_by_id_in(fetch_team_source("t1")).fetch("c1")).to eq("id" => "c1", "name" => "Alice", "salary" => 100)

      # A newer profile for the same coach omits `salary` (e.g. it was deleted upstream). It arrives as a non-empty
      # map with a null value, so re-applying it overwrites `salary` with null rather than leaving the v1 value.
      indexer.processor.process([coach_profile_event("c1", nil, version: 2)], refresh_indices: true)

      coaches_by_id = coaches_by_id_in(fetch_team_source("t1"))
      expect(coaches_by_id.fetch("c1")).to eq("id" => "c1", "name" => "Alice", "salary" => nil)
      # The sibling coach is unaffected by clearing c1's sourced value (and was never sourced, so no `salary`).
      expect(coaches_by_id.fetch("cø")).to eq("id" => "cø", "name" => "Bob")

      # A still-newer profile restores the value, confirming clearing isn't permanent.
      indexer.processor.process([coach_profile_event("c1", 150, version: 3)], refresh_indices: true)

      expect(coaches_by_id_in(fetch_team_source("t1")).fetch("c1")).to eq("id" => "c1", "name" => "Alice", "salary" => 150)
    end

    it "rejects a mutation of the relationship used by a nested `sourced_from` field" do
      indexer.processor.process([team_event], refresh_indices: true)
      indexer.processor.process([coach_profile_event("c1", 100, id: "prof-a")], refresh_indices: true)

      # A different source id for the same coach is a relationship mutation, which breaks out-of-order guarantees.
      expect {
        indexer.processor.process([coach_profile_event("c1", 200, id: "prof-b")], refresh_indices: true)
      }.to raise_error Indexer::IndexingFailuresError, a_string_including(
        "apparently changed", "mutations of relationships used with `sourced_from` are not supported"
      )
    end

    def team_event(version: nil)
      build_upsert_event(
        :team,
        id: "t1",
        league: league,
        formed_on: formed_on,
        staff: build(
          :staff,
          coaches: [
            build(:coach, id: "c1", name: "Alice"),
            build(:coach, id: "cø", name: "Bob")
          ],
          general_manager: build(:general_manager, id: "gm1", name: "Casey")
        ),
        **{__version: version}.compact
      )
    end

    def coach_profile_event(coach_id, annual_salary, id: "prof-#{coach_id}", version: nil)
      build_upsert_event(
        :coach_profile,
        id: id,
        team_id: "t1",
        coach_id: coach_id,
        annual_salary: annual_salary,
        team_league: league,
        team_formed_on: formed_on,
        **{__version: version}.compact
      )
    end

    # GM events are a distinct source type, matched purely by `team_id`.
    def gm_profile_event(annual_salary, version:)
      build_upsert_event(
        :general_manager_profile,
        __version: version,
        id: "prof-gm1",
        team_id: "t1",
        annual_salary: annual_salary,
        team_league: league,
        team_formed_on: formed_on
      )
    end

    def coaches_by_id_in(source)
      source.fetch("staff").fetch("coaches").to_h { |c| [c.fetch("id"), c] }
    end

    def fetch_team_source(id)
      main_datastore_client
        .msearch(body: [{index: "teams*"}, {query: {ids: {values: [id]}}}])
        .dig("responses", 0, "hits", "hits", 0, "_source")
    end
  end
end
