# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/event_id"

module ElasticGraph
  class Indexer
    RSpec.describe EventID do
      describe ".from_event", :factories do
        it "builds it from an event payload" do
          event = build_upsert_event(:widget, id: "abc", __version: 12)
          event_id = EventID.from_event(event)

          expect(event_id.type).to eq "Widget"
          expect(event_id.id).to eq "abc"
          expect(event_id.version).to eq 12
        end
      end

      describe "#to_s" do
        it "converts to the string form" do
          event_id = EventID.new(type: "Widget", id: "1234", version: 7)

          expect(event_id.to_s).to eq "Widget:1234@v7"
        end
      end
    end
  end
end
