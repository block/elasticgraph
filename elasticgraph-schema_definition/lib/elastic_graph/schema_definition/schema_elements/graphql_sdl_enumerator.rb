# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Responsible for enumerating the SDL strings for all GraphQL types, both explicitly defined and derived.
      #
      # @private
      class GraphQLSDLEnumerator
        include ::Enumerable
        # @dynamic schema_def_state
        attr_reader :schema_def_state

        def initialize(schema_def_state, all_types)
          @schema_def_state = schema_def_state
          @all_types = all_types
        end

        # Yields the SDL for each GraphQL type, including both explicitly defined
        # GraphQL types and derived GraphqL types.
        def each(&block)
          all_types = @all_types.sort_by(&:name)
          all_type_names = all_types.map(&:name).to_set

          all_types.each do |type|
            next if STOCK_GRAPHQL_SCALARS.include?(type.name)
            yield type.to_sdl { |arg| all_type_names.include?(arg.value_type.fully_unwrapped.name) }
          end
        end
      end
    end
  end
end
