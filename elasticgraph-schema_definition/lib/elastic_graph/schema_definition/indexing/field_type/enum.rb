# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # Contains implementation logic for the different types of indexing fields.
      #
      # @api private
      module FieldType
        # @!parse class Enum < ::Data; end
        Enum = ::Data.define(:enum_value_names)

        # Responsible for the JSON schema and mapping of a {SchemaElements::EnumType}.
        #
        # @!attribute [r] enum_value_names
        #   @return [Array<String>] list of names of values in this enum type.
        #
        # @api private
        class Enum < ::Data
          # @return [Hash<String, ::Object>] the datastore mapping for this enum type.
          def to_mapping
            {"type" => "keyword"}
          end

          # @dynamic initialize, enum_value_names
        end
      end
    end
  end
end
