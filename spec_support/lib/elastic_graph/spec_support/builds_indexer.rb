# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/builds_datastore_core"
require "elastic_graph/indexer"
require "elastic_graph/indexer/config"

module ElasticGraph
  module BuildsIndexer
    include BuildsDatastoreCore

    def build_indexer(
      datastore_core: nil,
      latency_slo_thresholds_by_timestamp_in_ms: {},
      skip_derived_indexing_type_updates: {},
      datastore_router: nil,
      clock: nil,
      monotonic_clock: nil,
      **datastore_core_options,
      &customize_datastore_config
    )
      Indexer.new(
        datastore_core: datastore_core || build_datastore_core(**datastore_core_options, &customize_datastore_config),
        config: Indexer::Config.new(
          latency_slo_thresholds_by_timestamp_in_ms: latency_slo_thresholds_by_timestamp_in_ms,
          skip_derived_indexing_type_updates: skip_derived_indexing_type_updates.transform_values(&:to_set)
        ),
        datastore_router: datastore_router,
        clock: clock,
        monotonic_clock: monotonic_clock
      )
    end
  end

  RSpec.configure do |c|
    c.include BuildsIndexer, :builds_indexer
  end
end
