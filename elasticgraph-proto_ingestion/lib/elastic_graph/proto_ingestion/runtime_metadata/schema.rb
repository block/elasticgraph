# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/runtime_metadata/type"

module ElasticGraph
  module ProtoIngestion
    module RuntimeMetadata
      # Configuration stored with the protobuf indexer extension.
      #
      # @private
      Schema = ::Data.define(:package_name, :types_by_name) do
        # @implements Schema

        def self.from_hash(hash)
          types = hash["types_by_name"] || {} # : ::Hash[::String, untyped]
          new(
            package_name: hash.fetch("package_name"),
            types_by_name: types.transform_values { |type| Type.from_hash(type) }
          )
        end

        def to_dumpable_hash
          hash = {"package_name" => package_name} # : ::Hash[::String, untyped]
          hash["types_by_name"] = types_by_name.sort.to_h.transform_values(&:to_dumpable_hash) unless types_by_name.empty?
          hash
        end
      end
    end
  end
end
