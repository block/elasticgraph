# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"
require "elastic_graph/spec_support/schema_definition_helpers"
require "graphql"

module ElasticGraph
  module SchemaDefinition
    ::RSpec.shared_context "GraphQL schema spec support" do
      include_context "SchemaDefinitionHelpers"

      def self.with_both_casing_forms(&block)
        context "with schema elements configured to use camelCase" do
          before(:context) { @schema_elements = SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: "camelCase") }
          attr_reader :schema_elements
          module_exec(:camelCase, &block)
        end

        context "with schema elements configured to use snake_case" do
          before(:context) { @schema_elements = SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: "snake_case") }
          attr_reader :schema_elements
          module_exec(:snake_case, &block)
        end
      end

      def raise_invalid_graphql_name_error_for(name)
        raise_error Errors::InvalidGraphQLNameError, a_string_including("Not a valid GraphQL name: `#{name}`", GRAPHQL_NAME_VALIDITY_DESCRIPTION)
      end

      def define_schema(**options, &block)
        define_schema_with_schema_elements(schema_elements, **options, &block).graphql_schema_string
      end

      def correctly_cased(name)
        schema_elements.normalize_case(name)
      end

      def types_defined_in(schema_string)
        ::GraphQL::Schema.from_definition(schema_string).types.keys
      end

      def grouped_by_type_from(sdl, source_type, include_docs: false)
        derived_graphql_type_def_from(sdl, source_type, "GroupedBy", include_docs: include_docs)
      end

      def aggregated_values_type_from(sdl, source_type, include_docs: false)
        derived_graphql_type_def_from(sdl, source_type, "AggregatedValues", include_docs: include_docs)
      end

      def connection_type_from(sdl, source_type, include_docs: false)
        derived_graphql_type_def_from(sdl, source_type, "Connection", include_docs: include_docs)
      end

      def edge_type_from(sdl, source_type, include_docs: false)
        derived_graphql_type_def_from(sdl, source_type, "Edge", include_docs: include_docs)
      end

      def list_filter_type_from(sdl, source_type, include_docs: false)
        filter_type_from(sdl, "#{source_type}List", include_docs: include_docs)
      end

      def list_element_filter_type_from(sdl, source_type, include_docs: false)
        filter_type_from(sdl, "#{source_type}ListElement", include_docs: include_docs)
      end

      def fields_list_filter_type_from(sdl, source_type, include_docs: false)
        filter_type_from(sdl, "#{source_type}FieldsList", include_docs: include_docs)
      end

      def filter_type_from(sdl, source_type, include_docs: false)
        derived_graphql_type_def_from(sdl, source_type, "FilterInput", include_docs: include_docs)
      end

      def aggregation_type_from(sdl, source_type, include_docs: false)
        derived_graphql_type_def_from(sdl, source_type, "Aggregation", include_docs: include_docs)
      end

      def sub_aggregation_type_from(sdl, source_type, include_docs: false)
        derived_graphql_type_def_from(sdl, source_type, "SubAggregation", include_docs: include_docs)
      end

      def aggregation_sub_aggregations_type_from(sdl, source_type, under: nil, include_docs: false)
        derived_graphql_type_def_from(sdl, source_type, "Aggregation#{under}SubAggregations", include_docs: include_docs)
      end

      def sub_aggregation_sub_aggregations_type_from(sdl, source_type, under: nil, include_docs: false)
        derived_graphql_type_def_from(sdl, source_type, "SubAggregation#{under}SubAggregations", include_docs: include_docs)
      end

      def aggregation_connection_type_from(sdl, source_type, include_docs: false)
        connection_type_from(sdl, "#{source_type}Aggregation", include_docs: include_docs)
      end

      def sub_aggregation_connection_type_from(sdl, source_type, include_docs: false)
        connection_type_from(sdl, "#{source_type}SubAggregation", include_docs: include_docs)
      end

      def aggregation_edge_type_from(sdl, source_type, include_docs: false)
        edge_type_from(sdl, "#{source_type}Aggregation", include_docs: include_docs)
      end

      def sub_aggregation_edge_type_from(sdl, source_type, include_docs: false)
        edge_type_from(sdl, "#{source_type}SubAggregation", include_docs: include_docs)
      end

      def sort_order_type_from(sdl, source_type, include_docs: false)
        derived_graphql_type_def_from(sdl, source_type, "SortOrderInput", include_docs: include_docs)
      end

      def derived_graphql_type_def_from(sdl, source_type, derived_graphql_type_suffix, include_docs: false)
        type_def_from(sdl, "#{source_type}#{derived_graphql_type_suffix}", include_docs: include_docs)
      end
    end
  end
end
