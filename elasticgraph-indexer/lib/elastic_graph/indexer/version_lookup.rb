# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class Indexer
    # A read-only target for finding an already-indexed source event's version.
    # It deliberately has no Event or method for building a datastore write.
    #
    # @!attribute [r] source_event_type
    #   @return [String] the source event's GraphQL type
    # @!attribute [r] destination_index_def
    #   @return [DatastoreCore::IndexDefinition] the index to search
    # @!attribute [r] update_target
    #   @return [SchemaArtifacts::RuntimeMetadata::UpdateTarget] the relationship whose version to read
    # @!attribute [r] doc_id
    #   @return [String] the destination document id
    class VersionLookup < ::Data.define(:source_event_type, :destination_index_def, :update_target, :doc_id)
      # @dynamic source_event_type, destination_index_def, update_target, doc_id

      # @return [Boolean] whether this target stores source event versions
      def versioned?
        update_target.for_normal_indexing?
      end
    end
  end
end
