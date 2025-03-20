# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/operation/result"
require "elastic_graph/support/hash_util"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  class Indexer
    module Operation
      Upsert = Support::MemoizableData.define(:event, :destination_index_def, :record_preparer) do
        # @implements Upsert

        def to_datastore_bulk
          @to_datastore_bulk ||= [{index: metadata}, prepared_record]
        end

        def categorize(response)
          index = response.fetch("index")
          status = index.fetch("status")

          case status
          when 200..299
            Result.success_of(self)
          when 409
            Result.noop_of(self, index.fetch("error").fetch("reason"))
          else
            Result.failure_of(self, index.fetch("error").fetch("reason"))
          end
        end

        def doc_id
          @doc_id ||= event.fetch("id")
        end

        def type
          :upsert
        end

        def description
          "#{event.fetch("type")} upsert"
        end

        def versioned?
          true
        end

        private

        def metadata
          @metadata ||= {
            _index: destination_index_def.index_name_for_writes(prepared_record),
            _id: doc_id,
            version: event.fetch("version"),
            version_type: "external",
            routing: destination_index_def.routing_value_for_prepared_record(prepared_record)
          }.compact
        end

        def prepared_record
          @prepared_record ||= record_preparer.prepare_for_index(event.fetch("type"), event.fetch("record"))
        end
      end
    end
  end
end
