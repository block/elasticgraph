# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion"

module ElasticGraph
  module ProtoIngestion
    # Namespace for all protobuf schema definition support.
    #
    # {SchemaDefinition::APIExtension} is the primary entry point and should be used as a schema definition extension module.
    module SchemaDefinition
      # Module designed to be extended onto an {ElasticGraph::SchemaDefinition::API} instance
      # to enable protobuf schema artifact generation.
      #
      # @note The protobuf schema artifact generation logic has not been implemented yet, so
      #   extending this module is currently a no-op.
      module APIExtension
      end
    end
  end
end
