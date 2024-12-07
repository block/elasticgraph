# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    module Filtering
      # Responsible for translating a `filter` expression from GraphQL field names to the internal
      # `name_in_index` of each field. This is necessary so that when a field is defined with
      # an alternate `name_in_index`, the query against the index uses that name even while
      # the name in the GraphQL schema is different.
      #
      # In addition, we translate the enum value names to enum value objects, so that any runtime
      # metadata associated with that enum value is available to our `FilterInterpreter`.
      class FilterArgsTranslator < ::Data.define(:filter_arg_name)
        def initialize(schema_element_names:)
          super(filter_arg_name: schema_element_names.filter)
        end

        # Translates the `filter` expression from the given `args` and `field` into their equivalent
        # form using the `name_in_index` for any fields that are named differently in the index
        # vs GraphQL.
        def translate_filter_args(field:, args:)
          return nil unless (filter_hash = args[filter_arg_name])
          filter_type = field.schema.type_from(field.graphql_field.arguments.fetch(filter_arg_name).type)
          convert(filter_type, filter_hash)
        end

        private

        def convert(parent_type, filter_object)
          case filter_object
          when ::Hash
            filter_object.to_h do |key, value|
              field = parent_type.field_named(key)
              [field.name_in_index.to_s, convert(field.type.unwrap_fully, value)]
            end
          when ::Array
            filter_object.map { |value| convert(parent_type, value) }
          when nil
            nil
          else
            if parent_type.enum?
              # Replace the name of an enum value with the value itself.
              parent_type.enum_value_named(filter_object)
            else
              filter_object
            end
          end
        end
      end
    end
  end
end
