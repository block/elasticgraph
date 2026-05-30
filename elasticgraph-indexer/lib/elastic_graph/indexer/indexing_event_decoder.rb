# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "json"

module ElasticGraph
  class Indexer
    module IndexingEventDecoder
      # Defines the extension interface implemented by indexing event decoders.
      #
      # @api private
      class Interface
        # :nocov:
        def initialize(config:, schema_artifacts:, logger:)
        end

        def decode(payload)
          []
        end
        # :nocov:
      end

      # The default indexing event decoder, which expects newline-delimited JSON objects.
      #
      # @api private
      class JSONLines
        def initialize(config:, schema_artifacts:, logger:)
        end

        def decode(payload)
          payload.split("\n").map { |event| JSON.parse(event) }
        end
      end
    end
  end
end
