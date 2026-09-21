# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  class Indexer
    # Indicates a payload that an ingestion adapter could not turn into an {Event} because its
    # envelope is malformed. When the adapter can validate its identity separately, a
    # {SupersessionCandidate} can check whether a newer indexed version supersedes this failure.
    class MalformedEventError < Errors::Error
      # @dynamic payload, event_id, message_id, main_message, message

      # The raw payload, in the ingestion adapter's format.
      attr_reader :payload

      # Best-effort description of the event id, built from whatever envelope fields were present.
      attr_reader :event_id

      # The id of the transport message that carried the payload, if known.
      attr_reader :message_id

      # The "main" part of the error message (without the id portion).
      attr_reader :main_message

      def initialize(payload:, event_id:, message_id:, main_message:)
        @payload = payload
        @event_id = event_id
        @message_id = message_id
        @main_message = main_message

        super("#{full_id}: #{main_message}")
      end

      def full_id
        message_id ? "#{event_id} (message_id: #{message_id})" : event_id
      end
    end
  end
end
