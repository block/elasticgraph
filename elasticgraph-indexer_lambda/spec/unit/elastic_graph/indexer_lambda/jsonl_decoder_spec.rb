# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer_lambda/jsonl_decoder"

module ElasticGraph
  module IndexerLambda
    RSpec.describe JSONLDecoder do
      describe "#decode_events" do
        it "parses JSON Lines payloads into ElasticGraph events" do
          decoder = described_class.new

          decoded_events = decoder.decode_events(
            sqs_record: {"messageId" => "123"},
            body: %({"id":"1"}\n{"id":"2","record":{"name":"Widget"}})
          )

          expect(decoded_events).to eq([
            {"id" => "1"},
            {"id" => "2", "record" => {"name" => "Widget"}}
          ])
        end

        it "returns no events for an empty message body" do
          decoder = described_class.new

          expect(
            decoder.decode_events(
              sqs_record: {"messageId" => "123"},
              body: ""
            )
          ).to eq([])
        end
      end
    end
  end
end
