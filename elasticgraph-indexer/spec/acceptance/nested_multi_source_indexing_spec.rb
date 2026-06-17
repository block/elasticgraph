# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  # Exercises *nested* `sourced_from`: fields sourced onto elements embedded within a `Team` document rather
  # than onto the root. A `Team` embeds a `Staff` object; each member's `career_wins` is sourced from a
  # separate records feed. The dotted embedding paths cover both shapes the painless script must navigate:
  # - `staff.coaches` (object then list): the target element is matched by id (`coachId`).
  # - `staff.general_manager` (all object): the target element is reached by field name (the all-object path).
  RSpec.describe "Nested multi-source indexing", :uses_datastore, :factories, :capture_logs do
    let(:indexer) { build_indexer }

    # A multi-byte character in a coach id, to verify the length-prefixed element-key encoding (which counts
    # UTF-16 code units) round-trips correctly when locating the embedded element.
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

      # Each `CoachRecord` carries the equivalents the indexer needs to route (`team_league`) and select the
      # rollover index (`team_formed_on`) for the `Team` update, plus the keys identifying the target element.
      record_for = ->(coach_id, wins) do
        build_upsert_event(
          :coach_record,
          id: "rec-#{coach_id}",
          teamId: "t1",
          coachId: coach_id,
          wins: wins,
          team_league: league,
          team_formed_on: formed_on
        )
      end

      record_c1 = record_for.call("c1", 100)
      record_c2 = record_for.call(multibyte_coach_id, 200)
      # The GM feed is a distinct source type, matched on the object path purely by `teamId`.
      record_gm = build_upsert_event(
        :general_manager_record,
        id: "rec-gm1",
        teamId: "t1",
        wins: 300,
        team_league: league,
        team_formed_on: formed_on
      )

      # Ingest a coach record BEFORE the team exists, to exercise the out-of-order buffer path: the sourced
      # data is buffered and applied once the team document is later created.
      indexer.processor.process([record_c1], refresh_indices: true)

      # Now the team itself.
      indexer.processor.process([team], refresh_indices: true)

      # And the remaining records after the team exists (the common in-order path), including the GM
      # (object path) and the multi-byte-id coach (list path).
      indexer.processor.process([record_c2, record_gm], refresh_indices: true)

      source = indexed_team_source("t1")

      expect(source["id"]).to eq("t1")

      staff = source.fetch("staff")
      coaches_by_id = staff.fetch("coaches").to_h { |c| [c.fetch("id"), c] }
      expect(coaches_by_id.keys).to contain_exactly("c1", multibyte_coach_id)

      # `c1`'s record arrived before the team doc; its sourced `career_wins` was buffered and applied on team creation.
      expect(coaches_by_id.fetch("c1")).to include("name" => "Alice", "career_wins" => 100)
      # The multi-byte id round-trips through the element-key encoding and the right element gets filled in.
      expect(coaches_by_id.fetch(multibyte_coach_id)).to include("name" => "Bjørn", "career_wins" => 200)

      # The all-object path: the singleton general manager element is reached by field name and filled in.
      expect(staff.fetch("general_manager")).to include("name" => "Casey", "career_wins" => 300)

      # The team document records each source it has seen. The relationship keys are the *qualified* nested
      # relationships (the dotted embedding path plus the leaf relationship name).
      expect(source.fetch("__sources")).to contain_exactly("__self", "staff.coaches.record", "staff.general_manager.record")

      # The core invariant of nested `sourced_from`: each nested element gets its *own* `__versions` bucket so
      # that sibling elements sharing a relationship (the two coaches, both via `staff.coaches.record`) don't
      # collide into one version bucket and trip the "relationship has changed" conflict check. Top-level events
      # (`__self`) stay keyed by the bare relationship; nested events extend the key with one identifier per
      # path segment and encode it (length-prefixed `len:value|` parts: each object segment contributes its
      # field name, each list segment the matched `coachId`). So the coach keys carry both the `staff` object
      # segment and the `coachId`, and the GM key carries both object segments (`staff`, `general_manager`).
      expect(source.fetch("__versions")).to eq(
        "__self" => {"t1" => version_of(team)},
        "20:staff.coaches.record|5:staff|2:c1|" => {"rec-c1" => version_of(record_c1)},
        "20:staff.coaches.record|5:staff|11:coach-bjørn|" => {"rec-#{multibyte_coach_id}" => version_of(record_c2)},
        "28:staff.general_manager.record|5:staff|15:general_manager|" => {"rec-gm1" => version_of(record_gm)}
      )
    end

    # The version an upsert event will record in the document's `__versions` map.
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
