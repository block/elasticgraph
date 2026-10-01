# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      module SchemaElements
        # Controls a field's protobuf source name independently of its public GraphQL name.
        module FieldExtension
          # Explicitly renames a compatible protobuf field, or rotates an incompatible one to a
          # fresh number. Historical protobuf names may not be reused for another wire contract.
          # @param name [String] protobuf field identifier
          # @return [void]
          def protobuf(name:)
            unless /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(name)
              raise Errors::SchemaError, "Invalid protobuf field name #{name.inspect}: expected a protobuf identifier."
            end
            @protobuf_name = name
          end

          # @return [String, nil] explicitly configured protobuf name
          # @dynamic protobuf_name
          attr_reader :protobuf_name

          # @return [Hash<String, Object>] effective historical wire contract
          # @dynamic protobuf_contract, protobuf_contract=
          attr_accessor :protobuf_contract
        end
      end
    end
  end
end
