# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/event_envelope"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Backward-compatible alias for the JSON ingestion event envelope helper.
      #
      # @api private
      EventEnvelope = JSONIngestion::SchemaDefinition::Indexing::EventEnvelope
    end
  end
end
