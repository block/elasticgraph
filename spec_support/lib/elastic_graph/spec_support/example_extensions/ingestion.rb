# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/ingestion_adapter"
require "elastic_graph/indexer/record_preparer"

module ElasticGraph
  module SpecSupport
    # Provides an ingestion format for tests with already prepared records.
    module ExampleIngestion
      class Adapter
        def validate_event(event, skip_record_validation: false)
          Indexer::IngestionAdapter::ValidationResult.valid(event, Indexer::RecordPreparer::Identity)
        end
      end

      module IndexerExtension
        def ingestion_adapters_by_format
          @ingestion_adapters_by_format ||= super.merge("example" => Adapter.new)
        end
      end

      module APIExtension
        def self.extended(api)
          api.register_indexer_extension IndexerExtension, defined_at: "elastic_graph/spec_support/example_extensions/ingestion"
        end
      end
    end
  end
end
