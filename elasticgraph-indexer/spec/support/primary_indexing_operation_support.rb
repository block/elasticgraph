# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class Indexer
    # Provides test support for building primary indexing operations.
    module PrimaryIndexingOperationSupport
      # Builds a primary indexing operation (Operation::Update) for the given event.
      #
      # @param event [Hash] The event hash containing "type", "id", and "record"
      # @param index_def [DatastoreCore::IndexDefinition, nil] The index definition to use.
      #   If not provided, it will be looked up automatically from the indexer.
      # @param idxr [Indexer, nil] The indexer instance to use. Defaults to `indexer` method.
      # @return [Operation::Update] The primary indexing operation
      def new_primary_indexing_operation(event, index_def: nil, idxr: indexer)
        update_targets = idxr
          .schema_artifacts
          .runtime_metadata
          .object_types_by_name
          .fetch(event.fetch("type"))
          .update_targets
          .select { |ut| ut.type == event.fetch("type") }

        expect(update_targets.size).to eq(1)

        index_def ||= idxr.datastore_core.index_definitions_by_graphql_type.fetch(event.fetch("type")).first

        Operation::Update.new(
          event: event,
          prepared_record: idxr.record_preparer_factory.for_latest_json_schema_version.prepare_for_index(
            event.fetch("type"),
            event.fetch("record")
          ),
          destination_index_def: index_def,
          update_target: update_targets.first,
          doc_id: event.fetch("id"),
          destination_index_mapping: idxr.schema_artifacts.index_mappings_by_index_def_name.fetch(index_def.name)
        )
      end
    end
  end
end
