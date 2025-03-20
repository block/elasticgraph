# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  class GraphQL
    module Resolvers
      # A class builder that is just like `Data` and also adapts itself to our
      # resolver interface. Can resolve any field that is defined in `schema_element_names`
      # and also has a corresponding method definition.
      module ResolvableValue
        # `MemoizableData.define` provides the following methods:
        # @dynamic schema_element_names

        def self.new(*fields, &block)
          Support::MemoizableData.define(:schema_element_names, *fields) do
            # @implements ResolvableValueClass
            include ResolvableValue
            class_exec(&block) if block
          end
        end

        def resolve(field:, object:, context:, args:, lookahead:)
          method_name = canonical_name_for(field.name, "Field")
          public_send(method_name, **args_to_canonical_form(args))
        end

        private

        def args_to_canonical_form(args)
          args.to_h do |key, value|
            [canonical_name_for(key, "Argument"), value]
          end
        end

        def canonical_name_for(name, element_type)
          schema_element_names.canonical_name_for(name) ||
            raise(Errors::SchemaError, "#{element_type} `#{name}` is not a defined schema element")
        end
      end
    end
  end
end
