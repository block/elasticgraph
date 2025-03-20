# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "graphql"

module ElasticGraph
  module QueryRegistry
    # Responsible for dumping structural information about query variables.
    #
    # This is necessary for the query registry to be able to support object and enum variables.
    # To understand why, consider what happens when a field is removed from an input object
    # variable used by a client's query. Whether or not it that will break the client depends
    # on which fields of the input object the client populates when sending the query to
    # ElasticGraph. Similarly, if an enum value is removed from an enum value variable used by
    # a client, it could be a breaking change (but only if the client ever passes the removed
    # enum value).
    #
    # To detect this situation, we use this to dump the structural information about all variables.
    # When the structure of variables changes, we can then tell the engineer that they need to verify
    # that it won't break the client.
    class VariableDumper
      def initialize(graphql_schema)
        @graphql_schema = graphql_schema
      end

      # Returns a hash of operations from the given query string. For each operation, the value
      # is a hash of variables.
      def dump_variables_for_query(query_string)
        query = ::GraphQL::Query.new(@graphql_schema, query_string, validate: false)

        if query.document.nil?
          # If the query was unparsable, we don't know anything about the variables and must just return an empty hash.
          {}
        else
          # @type var operations: ::Array[::GraphQL::Language::Nodes::OperationDefinition]
          operations = _ = query.document.definitions.grep(::GraphQL::Language::Nodes::OperationDefinition)
          dump_variables_for_operations(operations)
        end
      end

      # Returns a hash containing the variables for each operation.
      def dump_variables_for_operations(operations)
        operations.each_with_index.to_h do |operation, index|
          [operation.name || "(Anonymous operation #{index + 1})", variables_for_op(operation)]
        end
      end

      private

      # Returns a hash of variables for the given GraphQL operation.
      def variables_for_op(operation)
        operation.variables.sort_by(&:name).to_h do |variable|
          type_info =
            if (type = @graphql_schema.type_from_ast(variable.type))
              type_info(type)
            else
              # We should only get here if a variable references a type that is undefined. Since we
              # don't know anything about the type other than the name, that's all we can return.
              variable.type.to_query_string
            end

          [variable.name, type_info]
        end
      end

      # Returns information about the given type.
      #
      # Note that this is optimized for human readability over data structure consistency.
      # We don't *do* anything with this dumped data (other than comparing its equality
      # against the dumped results for the same query in the future), so we don't need
      # the sort of data structure consistency we'd normally want.
      #
      # For scalars (and lists-of-scalars) the *only* meaningful structural information
      # is the type signature (e.g. `[ID!]`). On the other hand, we need the `fields` for
      # an input object, and the `values` for an enum (along with the type signature for
      # those, to distinguish list vs not and nullable vs not).
      #
      # So, while we return a hash for object/enum variables, for all others we just return
      # the type signature string.
      def type_info(type)
        unwrapped_type = type.unwrap

        if unwrapped_type.kind.input_object?
          {"type" => type.to_type_signature, "fields" => fields_for(_ = unwrapped_type)}
        elsif unwrapped_type.kind.enum?
          {"type" => type.to_type_signature, "values" => (_ = unwrapped_type).values.keys.sort}
        else
          type.to_type_signature
        end
      end

      # Returns a hash of input object fields for the given type.
      def fields_for(variable_type)
        variable_type.arguments.values.sort_by(&:name).to_h do |arg|
          if arg.type.unwrap == variable_type
            # Don't recurse (it would never terminate); just dump a reference to the type.
            [arg.name, arg.type.to_type_signature]
          else
            [arg.name, type_info(arg.type)]
          end
        end
      end
    end
  end
end
