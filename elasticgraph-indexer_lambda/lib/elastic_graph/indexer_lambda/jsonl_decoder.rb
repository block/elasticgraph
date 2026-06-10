# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "json"

module ElasticGraph
  module IndexerLambda
    # Decodes SQS message payloads encoded as JSON Lines into ElasticGraph events.
    #
    # `SqsProcessor` accepts alternate decoders that implement the same
    # `#decode_events(sqs_record:, body:)` contract and return event hashes.
    #
    # @private
    class JSONLDecoder
      # Decodes the given message payload into zero or more ElasticGraph events.
      #
      # @param sqs_record [Hash] full SQS record carrying the payload
      # @param body [String] resolved SQS message body
      # @return [Array<Hash>] decoded ElasticGraph events
      def decode_events(sqs_record:, body:)
        _ = sqs_record
        body.split("\n").map { |event| JSON.parse(event) }
      end
    end
  end
end
