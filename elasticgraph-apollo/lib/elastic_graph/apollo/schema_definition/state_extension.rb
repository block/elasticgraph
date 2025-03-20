# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Apollo
    module SchemaDefinition
      # Extension module applied to `ElasticGraph::SchemaDefinition::State` to support extra Apollo state.
      #
      # @private
      module StateExtension
        # @dynamic apollo_directive_definitions, apollo_directive_definitions=
        attr_accessor :apollo_directive_definitions

        def self.extended(state)
          state.apollo_directive_definitions = [] # Ensure it's never `nil`.
        end
      end
    end
  end
end
