# Copyright 2024 - 2026 Block, Inc.
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
      describe ".from_decoded_hash" do
        it "builds it from a decoded payload" do
          event_id = EventID.from_decoded_hash({"type" => "Widget", "id" => "abc", "version" => 12})

          expect(event_id).to eq EventID.new(type: "Widget", id: "abc", version: 12)
        end

        # The payload it describes failed envelope validation, so any envelope field can be absent.
        it "leaves out the envelope fields the payload omits" do
          event_id = EventID.from_decoded_hash({"type" => "Widget"})

          expect(event_id).to eq EventID.new(type: "Widget", id: nil, version: nil)
          expect(event_id.to_s).to eq "Widget:@v"
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
