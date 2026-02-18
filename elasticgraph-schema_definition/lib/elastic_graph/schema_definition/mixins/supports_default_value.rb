# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/graphql_formatter"

module ElasticGraph
  module SchemaDefinition
    module Mixins
      # A mixin designed to be included in a schema element class that supports default values.
      module SupportsDefaultValue
        # Used to specify the default value for this field or argument.
        #
        # @param default_value [Object] default value for this field or argument
        # @return [void]
        def default(default_value)
          @default_value = default_value
        end

        # Generates SDL for the default value. Suitable for inclusion in the schema elememnts `#to_sdl`.
        #
        # @return [String]
        def default_value_sdl
          return nil unless instance_variable_defined?(:@default_value)
          " = #{Support::GraphQLFormatter.serialize(@default_value)}"
        end
      end
    end
  end
end
