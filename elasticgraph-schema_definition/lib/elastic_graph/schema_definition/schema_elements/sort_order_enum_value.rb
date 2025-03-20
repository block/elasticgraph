# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/schema_definition/mixins/has_readable_to_s_and_inspect"
require "elastic_graph/schema_definition/schema_elements/enum_value"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Simple wrapper around an {EnumValue} so that we can expose the `sort_order_field_path` to {Field} customization callbacks.
      class SortOrderEnumValue < DelegateClass(EnumValue)
        include Mixins::HasReadableToSAndInspect.new { |v| v.name }

        # @dynamic sort_order_field_path

        # @return [Array<Field>] path to the field from the root of the indexed {ObjectType}
        attr_reader :sort_order_field_path

        # @private
        def initialize(enum_value, sort_order_field_path)
          # We've told steep that SortOrderEnumValue is subclass of EnumValue
          # but here are supering to the `DelegateClass`'s initialize, not `EnumValue`'s,
          # so we have to use `__skip__`
          __skip__ = super(enum_value)
          @sort_order_field_path = sort_order_field_path
        end
      end
    end
  end
end
