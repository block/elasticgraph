# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SpecSupport
    # Reuses JSON record preparers within an example, keyed by schema artifacts.
    module JSONRecordPreparation
      def latest_json_record_preparer_for(indexer)
        require "elastic_graph/json_ingestion/record_preparer_factory"

        preparers = @latest_json_record_preparers_by_schema_artifacts ||= {}
        preparers[indexer.schema_artifacts] ||= JSONIngestion::RecordPreparerFactory.new(indexer.schema_artifacts).for_latest_json_schema_version
      end
    end
  end
end
