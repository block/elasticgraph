# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module ProtoIngestion
    # Indexer extension that schemas using {SchemaDefinition::APIExtension} register in their runtime
    # metadata, configured with the ingestion facts that protobuf descriptors cannot express. It does
    # not yet install a protobuf ingestion adapter.
    module IndexerExtension
    end
  end
end
