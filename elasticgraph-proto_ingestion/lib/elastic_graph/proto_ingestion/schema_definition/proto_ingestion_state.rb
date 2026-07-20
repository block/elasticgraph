# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Holds the proto ingestion extension's schema definition state.
      #
      # @private
      class ProtoIngestionState < ::Struct.new(:package_name)
      end
    end
  end
end
