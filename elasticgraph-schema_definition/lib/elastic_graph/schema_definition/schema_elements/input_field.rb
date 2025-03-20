# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/schema_definition/mixins/supports_default_value"
require "elastic_graph/schema_definition/schema_elements/field"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # A decorator that wraps a `Field` in order to provide additional functionality that
      # we need to support on fields on input types (but not on fields on return types).
      #
      # For example, fields on input types support default values, but return type fields do not.
      #
      # @private
      class InputField < DelegateClass(Field)
        prepend Mixins::SupportsDefaultValue

        def to_sdl(type_structure_only: false, default_value_sdl: self.default_value_sdl, &arg_selector)
          super(type_structure_only: type_structure_only, default_value_sdl: default_value_sdl, &arg_selector)
        end
      end
    end
  end
end
