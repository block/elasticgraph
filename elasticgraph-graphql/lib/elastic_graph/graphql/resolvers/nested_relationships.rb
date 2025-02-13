# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/relay_connection"

module ElasticGraph
  class GraphQL
    module Resolvers
      # Responsible for loading nested relationships that are stored as separate documents
      # in the datastore. We use `QuerySource` for the datastore queries to avoid
      # the N+1 query problem (giving us one datastore query per layer of our graph).
      #
      # Most of the logic for this lives in ElasticGraph::Schema::RelationJoin.
      class NestedRelationships
        def initialize(resolver_query_adapter:, schema_element_names:, logger:)
          @resolver_query_adapter = resolver_query_adapter
          @schema_element_names = schema_element_names
          @logger = logger
        end

        def call(field, object, args, context)
          log_warning = ->(**options) { log_field_problem_warning(field: field, **options) }
          join = field.relation_join
          id_or_ids = join.extract_id_or_ids_from(object, log_warning)
          filters = [
            build_filter(join.filter_id_field_name, nil, join.foreign_key_nested_paths, Array(id_or_ids)),
            join.additional_filter
          ].reject(&:empty?)

          lookahead = args.fetch(:lookahead)
          args = field.args_to_schema_form(args.except(:lookahead))
          query = @resolver_query_adapter
            .build_query_from(field: field, args: args, lookahead: lookahead, context: context)
            .merge_with(filters: filters)

          response =
            case id_or_ids
            when nil, []
              join.blank_value
            else
              initial_response = QuerySource.execute_one(query, for_context: context)
              join.normalize_documents(initial_response) do |problem|
                log_warning.call(document: {"id" => id_or_ids}, problem: "got #{problem} from the datastore search query")
              end
            end

          RelayConnection.maybe_wrap(response, field: field, context: context, lookahead: lookahead, query: query)
        end

        private

        def log_field_problem_warning(field:, document:, problem:)
          id = document.fetch("id", "<no id>")
          @logger.warn "#{field.parent_type.name}(id: #{id}).#{field.name} had a problem: #{problem}"
        end

        def build_filter(path, previous_nested_path, nested_paths, ids)
          if nested_paths.empty?
            path = path.delete_prefix("#{previous_nested_path}.") if previous_nested_path
            {path => {@schema_element_names.equal_to_any_of => ids}}
          else
            next_nested_path, *rest_nested_paths = nested_paths
            sub_filter = build_filter(path, next_nested_path, rest_nested_paths, ids)
            next_nested_path = next_nested_path.delete_prefix("#{previous_nested_path}.") if previous_nested_path
            {next_nested_path => {@schema_element_names.any_satisfy => sub_filter}}
          end
        end
      end
    end
  end
end
