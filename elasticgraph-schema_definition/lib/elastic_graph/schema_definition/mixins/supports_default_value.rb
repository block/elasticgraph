# Copyright 2024 - 2025 Block, Inc.
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
      # Designed to be `prepended` so that it can hook into `initialize`.
      module SupportsDefaultValue
        # @private
        def initialize(...)
          __skip__ = super # steep can't type this.
          @default_value = NO_DEFAULT_PROVIDED
        end

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
          return nil if @default_value == NO_DEFAULT_PROVIDED
          " = #{Support::GraphQLFormatter.serialize(@default_value)}"
        end

        private

        # A sentinel value that we can use to detect when a default has been provided.
        # We can't use `nil` to detect if a default has been provided because `nil` is a valid default value!
        NO_DEFAULT_PROVIDED = Module.new
      end
    end
  end
end
