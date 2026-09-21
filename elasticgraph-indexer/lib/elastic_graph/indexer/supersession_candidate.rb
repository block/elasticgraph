# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class Indexer
    # Recovery information for a rejected payload. This is never an indexable Event.
    #
    # @!attribute [r] failure
    #   @return [MalformedEventError] the original failure, including its raw payload
    # @!attribute [r] event_id
    #   @return [EventID] the validated identity of the rejected payload
    # @!attribute [r] versioned_operations
    #   @return [Array<VersionLookup>] the targets whose stored versions must supersede this payload
    class SupersessionCandidate < ::Data.define(:failure, :event_id, :versioned_operations)
      # @dynamic failure, event_id, versioned_operations

      # @return [Integer] the rejected payload's validated version
      def version
        event_id.version
      end
    end
  end
end
