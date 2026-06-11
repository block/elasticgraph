# Copyright 2024 - 2026 Block, Inc.
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
      schema_definition_extension_modules: nil,
      **datastore_core_options,
      &customize_datastore_config
    )
      datastore_core ||= build_datastore_core(
        schema_definition_extension_modules: schema_definition_extension_modules || default_indexer_schema_definition_extension_modules,
        **datastore_core_options,
        &customize_datastore_config
      )

      Indexer.new(
        datastore_core: datastore_core,
        config: Indexer::Config.new(
          latency_slo_thresholds_by_timestamp_in_ms: latency_slo_thresholds_by_timestamp_in_ms,
          skip_derived_indexing_type_updates: skip_derived_indexing_type_updates
        ),
        datastore_router: datastore_router,
        clock: clock,
        monotonic_clock: monotonic_clock
      )
    end

    private

    # The indexer can only ingest JSON events today, so artifacts generated for an indexer must
    # include the JSON schemas; this is the one spec builder that opts into the extension by default.
    # The require is lazy so that gems whose bundles do not include `elasticgraph-json_ingestion`
    # can still use this builder with an externally built `datastore_core:`.
    def default_indexer_schema_definition_extension_modules
      require "elastic_graph/json_ingestion/schema_definition/api_extension"
      [JSONIngestion::SchemaDefinition::APIExtension]
    end
  end

  RSpec.configure do |c|
    c.include BuildsIndexer, :builds_indexer
  end
end
