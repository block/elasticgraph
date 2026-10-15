# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module ProtoIngestion
    module RuntimeMetadata
      # Ingestion facts for a protobuf field that its descriptor cannot express.
      #
      # @private
      Field = ::Data.define(:name_in_index, :type) do
        # @implements Field

        def initialize(name_in_index: nil, type: nil)
          super
        end

        def self.from_hash(hash)
          new(name_in_index: hash["name_in_index"], type: hash["type"])
        end

        def to_dumpable_hash
          {"name_in_index" => name_in_index, "type" => type}.compact
        end
      end
    end
  end
end
