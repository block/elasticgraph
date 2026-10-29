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
      # The full ElasticGraph type signature and index name of a protobuf field.
      #
      # The unwrapped `type` references a key in Schema#types_by_name.
      #
      # @private
      Field = ::Data.define(:name_in_index, :type) do
        # @implements Field

        def self.from_hash(hash)
          new(name_in_index: hash.fetch("name_in_index"), type: hash.fetch("type"))
        end

        def to_dumpable_hash
          {"name_in_index" => name_in_index, "type" => type}
        end
      end
    end
  end
end
