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
      # Abstraction responsible for identifying paths to sub-aggregations, and, on that basis, determining
      # what the type names should be.
      #
      # @private
      SubAggregationPath = ::Data.define(
        # List of index document types within which the target type exists. This contains the set of parent
        # index document types--that is, types which are indexed or are themselves used as a `nested` field
        # on a parent of it. Parent objects which are not "index documents" (e.g. directly at an index level
        # or a nested field level) are omitted; we omit them because we don't offer sub-aggregations for such
        # a field, and the set of sub-aggregations we are going to offer is the basis for generating separate
        # `*SubAggregation` types.
        :parent_doc_types,
        # List of fields forming a path from the last parent doc type.
        :field_path
      ) do
        # @implements SubAggregationPath

        # Determines the set of sub aggregation paths for the given type.
        def self.paths_for(type, schema_def_state:)
          root_paths = type.indexed? ? [SubAggregationPath.new([type.name], [])] : [] # : ::Array[SubAggregationPath]

          non_relation_field_refs = schema_def_state
            .user_defined_field_references_by_type_name.fetch(type.name) { [] }
            # Relationship fields are the only case where types can reference each other in circular fashion.
            # If we don't reject that case here, we can get stuck in infinite recursion.
            .reject(&:relationship)

          root_paths + non_relation_field_refs.flat_map do |field_ref|
            # Here we call `schema_def_state.sub_aggregation_paths_for` rather than directly
            # recursing to give schema_def_state a chance to cache the results.
            parent_paths = schema_def_state.sub_aggregation_paths_for(field_ref.parent_type)

            if field_ref.nested?
              parent_paths.map { |path| path.plus_parent(field_ref.type_for_derived_types.fully_unwrapped.name) }
            else
              parent_paths.map { |path| path.plus_field(field_ref) }
            end
          end
        end

        def plus_parent(parent)
          with(parent_doc_types: parent_doc_types + [parent], field_path: [])
        end

        def plus_field(field)
          with(field_path: field_path + [field])
        end

        def field_path_string
          field_path.map(&:name).join(".")
        end
      end
    end
  end
end
