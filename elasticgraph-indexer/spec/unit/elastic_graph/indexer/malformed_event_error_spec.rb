# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/malformed_event_error"

module ElasticGraph
  class Indexer
    RSpec.describe MalformedEventError do
      it "describes the payload by its event id and message id when the message id is known" do
        error = MalformedEventError.new(
          payload: {"type" => "Widget", "id" => "w1"},
          event_id: "Widget:w1@v",
          message_id: "m1",
          main_message: "Malformed event payload. Missing `version`."
        )

        expect(error.message).to eq("Widget:w1@v (message_id: m1): Malformed event payload. Missing `version`.")
        expect(error.payload).to eq({"type" => "Widget", "id" => "w1"})
        expect(error.message_id).to eq("m1")
      end

      it "describes the payload by its event id alone when the message id is unknown" do
        error = MalformedEventError.new(
          payload: {},
          event_id: "Widget:w1@v",
          message_id: nil,
          main_message: "Malformed event payload."
        )

        expect(error.message).to eq("Widget:w1@v: Malformed event payload.")
        expect(error.message_id).to be nil
      end
    end
  end
end
