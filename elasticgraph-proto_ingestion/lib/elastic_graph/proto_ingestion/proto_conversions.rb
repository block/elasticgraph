# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module ProtoIngestion
    # Shared conversions between protobuf names and ElasticGraph names.
    #
    # @private
    module ProtoConversions
      # Recovers a standard ElasticGraph enum value name by removing its enum's prefix.
      # Non-standard names must be looked up in runtime metadata instead.
      #
      # @param proto_name [String] protobuf enum value name
      # @param enum_value_prefix [String] normalized prefix of the containing enum
      # @return [String]
      def self.enum_value_to_eg_name(proto_name, enum_value_prefix)
        proto_name.delete_prefix("#{enum_value_prefix}_")
      end
    end
  end
end
