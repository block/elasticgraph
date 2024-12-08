# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql/filtering/filter_value_set_extractor"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  class GraphQL
    class QueryAdapter
      class Filters < Support::MemoizableData.define(:schema_element_names, :filter_args_translator, :filter_node_interpreter)
        def call(field:, query:, args:, lookahead:, context:)
          filter_from_args = filter_args_translator.translate_filter_args(field: field, args: args)
          automatic_filter = build_automatic_filter(filter_from_args: filter_from_args, query: query)
          filters = [filter_from_args, automatic_filter].compact
          return query if filters.empty?

          query.merge_with(filters: filters)
        end

        private

        def build_automatic_filter(filter_from_args:, query:)
          # If an incomplete document could be hit by a search with our filters against any of the
          # index definitions, we must add a filter that will exclude incomplete documents.
          exclude_incomplete_docs_filter if query
            .search_index_definitions
            .any? { |index_def| search_could_hit_incomplete_docs?(index_def, filter_from_args || {}) }
        end

        def exclude_incomplete_docs_filter
          {"__sources" => {schema_element_names.equal_to_any_of => [SELF_RELATIONSHIP_NAME]}}
        end

        # Indicates if a search against the given `index_def` using the given `filter_from_args`
        # could hit an incomplete document.
        def search_could_hit_incomplete_docs?(index_def, filter_from_args)
          # If the index definition doesn't allow any searches to hit incomplete documents, we
          # can immediately return `false` without checking the filters.
          return false unless index_def.searches_could_hit_incomplete_docs?

          # ...otherwise, we have to look at how we are filtering. An incomplete document will have `null`
          # values for all fields with a `SELF_RELATIONSHIP_NAME` source. Therefore, if we filter on a
          # self-sourced field in a way that excludes documents with a `null` value, the search cannot
          # hit incomplete documents. However, when in doubt we'd rather return `true` as that's the safer
          # value to return (no bugs will result from returning `true` when we could have returned `false`,
          # but the query may not be as efficient as we'd like).
          #
          # Here we determine what field paths we need to check (e.g. only those field paths that are against
          # self-sourced fields).
          paths_to_check = determine_paths_to_check(filter_from_args, index_def.fields_by_path)

          # If we have no paths to check, then our filters don't exclude incomplete documents and we must return `true`.
          return true if paths_to_check.empty?

          # Finally, we look over each path. If all our filters allow the search to match documents that have `nil`
          # at that path, then the search can hit incomplete documents. But if even one path excludes documents
          # that have a `null` value for the field, we can safely return `false` for a more efficient query.
          paths_to_check.all? { |path| can_match_nil_values_at?(path, filter_from_args) }
        end

        # Figures out which field paths we need to check to see if a filter on it could match an incomplete document.
        # This method returns the set intersection of:
        #
        # - The field paths we are filtering on.
        # - The field paths that are sourced from `SELF_RELATIONSHIP_NAME`.
        def determine_paths_to_check(expression, index_fields_by_path, parent_path: nil)
          return [] unless expression.is_a?(::Hash)

          expression.compact.flat_map do |field_or_op, sub_expression|
            if filter_node_interpreter.identify_node_type(field_or_op, sub_expression) == :sub_field
              path = parent_path ? "#{parent_path}.#{field_or_op}" : field_or_op
              if (index_field = index_fields_by_path[path])
                # We've recursed down to a leaf field path. We want that path to be returned if the
                # field is sourced from SELF_RELATIONSHIP_NAME.
                (index_field.source == SELF_RELATIONSHIP_NAME) ? [path] : []
              else
                determine_paths_to_check(sub_expression, index_fields_by_path, parent_path: path)
              end
            elsif sub_expression.is_a?(::Array)
              sub_expression.flat_map do |sub_filter|
                determine_paths_to_check(sub_filter, index_fields_by_path, parent_path: parent_path)
              end
            else
              determine_paths_to_check(sub_expression, index_fields_by_path, parent_path: parent_path)
            end
          end
        end

        # Indicates if the given `filter` can match `nil` values at the given `path`. We rely
        # on `filter_value_set_extractor` to determine it, since it understands the semantics
        # of `any_of`, `not`, etc.
        def can_match_nil_values_at?(path, filter)
          value_set = filter_value_set_extractor.extract_filter_value_set([filter], [path])
          (_ = value_set).nil? || value_set.includes_nil?
        end

        def filter_value_set_extractor
          @filter_value_set_extractor ||=
            Filtering::FilterValueSetExtractor.new(
              filter_node_interpreter,
              schema_element_names,
              IncludesNilSet,
              ExcludesNilSet
            ) do |operator, filter_value|
              if operator == :equal_to_any_of && filter_value.include?(nil)
                IncludesNilSet
              else
                ExcludesNilSet
              end
            end
        end

        # Mixin for use with our set implementations that only care about if `nil` is an included value or not.
        module NilFocusedSet
          def union(other)
            (includes_nil? || other.includes_nil?) ? IncludesNilSet : ExcludesNilSet
          end

          def intersection(other)
            (includes_nil? && other.includes_nil?) ? IncludesNilSet : ExcludesNilSet
          end
        end

        # A representation of a set that includes `nil`.
        module IncludesNilSet
          extend NilFocusedSet

          # Methods provided by `extend NilFocusedSet`
          # @dynamic self.union, self.intersection

          def self.negate
            ExcludesNilSet
          end

          def self.includes_nil?
            true
          end
        end

        # A representation of a set that excludes `nil`.
        module ExcludesNilSet
          extend NilFocusedSet

          # Methods provided by `extend NilFocusedSet`
          # @dynamic self.union, self.intersection

          def self.negate
            IncludesNilSet
          end

          def self.includes_nil?
            false
          end
        end
      end
    end
  end
end
