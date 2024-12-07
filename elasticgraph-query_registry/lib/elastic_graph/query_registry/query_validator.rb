# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/query_registry/variable_backward_incompatibility_detector"
require "elastic_graph/query_registry/variable_dumper"
require "graphql"

module ElasticGraph
  module QueryRegistry
    class QueryValidator
      def initialize(schema, require_eg_latency_slo_directive:)
        @graphql_schema = schema.graphql_schema
        @schema_element_names = schema.element_names
        @var_dumper = VariableDumper.new(@graphql_schema)
        @var_incompat_detector = VariableBackwardIncompatibilityDetector.new
        @require_eg_latency_slo_directive = require_eg_latency_slo_directive
      end

      def validate(query_string, previously_dumped_variables:, client_name:, query_name:)
        # We pass `validate: false` since we do query validation on the operation level down below.
        query = ::GraphQL::Query.new(@graphql_schema, query_string, validate: false)

        if query.document.nil?
          {nil => query.static_errors.map(&:to_h)}
        else
          # @type var fragments: ::Array[::GraphQL::Language::Nodes::FragmentDefinition]
          # @type var operations: ::Array[::GraphQL::Language::Nodes::OperationDefinition]
          fragments, operations = _ = query.document.definitions.partition do |definition|
            definition.is_a?(::GraphQL::Language::Nodes::FragmentDefinition)
          end

          newly_dumped_variables = @var_dumper.dump_variables_for_operations(operations)

          operations.to_h do |operation|
            errors = if operation.name.nil?
              [{"message" => "The query has no named operations. We require all registered queries to be named for more useful logging."}]
            else
              variables_errors = variables_errors_for(_ = operation.name, previously_dumped_variables, newly_dumped_variables, client_name, query_name)
              directive_errors = directive_errors_for(operation)

              static_validation_errors_for(query, operation, fragments) + variables_errors + directive_errors
            end

            [operation.name, errors]
          end
        end
      end

      private

      def variables_errors_for(operation_name, old_dumped_variables, new_dumped_variables, client_name, query_name)
        rake_task = "rake \"query_registry:dump_variables[#{client_name}, #{query_name}]\""

        if old_dumped_variables.nil? || old_dumped_variables[operation_name].nil?
          return [{"message" => "No dumped variables for this operation exist. Correct by running: `#{rake_task}`"}]
        end

        old_op_vars = old_dumped_variables.fetch(operation_name)
        new_op_vars = new_dumped_variables.fetch(operation_name)

        if old_op_vars == new_op_vars
          # The previously dumped variables are up-to-date. No errors in this case.
          []
        elsif (incompatibilities = @var_incompat_detector.detect(old_op_vars: old_op_vars, new_op_vars: new_op_vars)).any?
          # The structure of variables has changed in a way that may break the client. Tell the user to verify with them.
          descriptions = incompatibilities.map(&:description).join(", ")
          [{
            "message" => "The structure of the query variables have had backwards-incompatible changes that may break `#{client_name}`: #{descriptions}. " \
            "To proceed, check with the client to see if this change is compatible with their logic, then run `#{rake_task}` to update the dumped info."
          }]
        else
          # The change to the variables shouldn't break the client, but we still need to keep the file up-to-date.
          [{"message" => "The variables file is out-of-date, but the changes to them should not impact `#{client_name}`. Run `#{rake_task}` to update the file."}]
        end
      end

      def directive_errors_for(operation)
        if @require_eg_latency_slo_directive && operation.directives.none? { |dir| dir.name == @schema_element_names.eg_latency_slo }
          [{"message" => "Your `#{operation.name}` operation is missing the required `@#{@schema_element_names.eg_latency_slo}(#{@schema_element_names.ms}: Int!)` directive."}]
        else
          []
        end
      end

      def static_validation_errors_for(query, operation, fragments)
        # Build a document with just this operation so that we can validate it in isolation, apart from the other operations.
        document = query.document.merge(definitions: [operation] + fragments)
        query = ::GraphQL::Query.new(@graphql_schema, nil, document: document, validate: false)
        @graphql_schema.static_validator.validate(query).fetch(:errors).map(&:to_h)
      end
    end
  end
end
