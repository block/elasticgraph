# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  # Pluggable JSON Schema ingestion serializer for ElasticGraph.
  #
  # This gem extracts the JSON Schema generation and validation logic from ElasticGraph's
  # core into a pluggable extension, following the same pattern as `elasticgraph-warehouse`
  # and `elasticgraph-apollo`. This is the first step toward supporting alternative ingestion
  # serializers (e.g., Protocol Buffers). Higher-level schema-definition entry points use it by
  # default for backward compatibility.
  module JSONIngestion
  end
end
