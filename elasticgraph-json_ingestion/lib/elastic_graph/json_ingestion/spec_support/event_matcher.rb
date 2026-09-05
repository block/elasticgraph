# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/ingestion_adapter"
require "json"

# Defines an RSpec matcher that can be used to validate ElasticGraph JSON events.
::RSpec::Matchers.define :be_a_valid_elastic_graph_event do |for_indexer:|
  match do |event|
    ingestion_adapter = ElasticGraph::JSONIngestion::IngestionAdapter.new(
      schema_artifacts: for_indexer.schema_artifacts,
      logger: for_indexer.logger,
      configure_record_validator: block_arg
    )

    result = for_indexer
      .operation_factory
      .with(ingestion_adapters: [ingestion_adapter])
      .build(event)

    @validation_failure = result.failed_event_error
    !@validation_failure
  end

  description do
    "be a valid ElasticGraph event"
  end

  failure_message do |event|
    <<~EOS
      expected the event[1] to #{description}, but it was invalid[2].

      [1] #{::JSON.pretty_generate(event)}

      [2] #{@validation_failure.message}
    EOS
  end

  failure_message_when_negated do |event|
    <<~EOS
      expected the event[1] not to #{description}, but it was valid.

      [1] #{::JSON.pretty_generate(event)}
    EOS
  end
end
