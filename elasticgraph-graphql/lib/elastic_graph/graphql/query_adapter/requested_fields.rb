# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    class QueryAdapter
      # Query adapter that populates the `requested_fields` attribute of an `DatastoreQuery` in
      # order to limit what fields we fetch from the datastore to only those that we actually
      # need to satisfy the GraphQL query. This results in more efficient datastore queries,
      # similar to doing `SELECT f1, f2, ...` instead of `SELECT *` for a SQL query.
      class RequestedFields
        # Partially applied `RequestedFields` -- essentially the `RequestedFields` without the schema,
        # so that it can be instantiated before the `Schema` instance exists, instead providing it from
        # `context` at query time.
        class WithoutSchema
          def call(field:, query:, lookahead:, args:, context:)
            return query if field.type.unwrap_fully.indexed_aggregation?

            RequestedFields.new(context.fetch(:elastic_graph_schema)).call(
              field: field,
              query: query,
              lookahead: lookahead,
              args: args,
              context: context
            )
          end
        end

        def initialize(schema)
          @schema = schema
        end

        def call(field:, query:, lookahead:, args:, context:)
          attributes = query_attributes_for(field: field, lookahead: lookahead)
          query.merge_with(**attributes)
        end

        def query_attributes_for(field:, lookahead:)
          attributes =
            if field.type.relay_connection?
              highlights = lookahead
                .selection(@schema.element_names.edges)
                .selection(@schema.element_names.highlights)

              {
                individual_docs_needed: pagination_fields_need_individual_docs?(lookahead),
                requested_fields: requested_fields_under(relay_connection_node_from(lookahead)),
                request_all_highlights: requesting_all_highlights?(lookahead),
                requested_highlights: requested_fields_under(highlights)
              }
            else
              {
                requested_fields: requested_fields_under(lookahead)
              }
            end

          attributes.merge(total_document_count_needed: query_needs_total_document_count?(lookahead))
        end

        private

        # Identifies the fields we need to fetch from the datastore by looking for the fields
        # under the given `node`.
        #
        # For nested relation fields, it is important that we start with this method, instead of
        # `requested_fields_for`, because they need to be treated differently if we are building
        # an `DatastoreQuery` for the nested relation field, or for a parent type.  When we determine
        # requested fields for a nested relation field, we need to look at its child fields, and we
        # can ignore its foreign key; but when we are determining requested fields for a parent type,
        # we need to identify the foreign key to request from the datastore, without recursing into
        # its children.
        def requested_fields_under(node, path_prefix: "")
          fields = node.selections.flat_map do |child|
            requested_fields_for(child, path_prefix: path_prefix)
          end

          fields << "#{path_prefix}__typename" if field_for(node.field)&.type&.abstract?
          fields
        end

        # Identifies the fields we need to fetch from the datastore for the given node,
        # and recursing into the fields under it as needed.
        def requested_fields_for(node, path_prefix:)
          return [] if graphql_dynamic_field?(node)

          # @type var field: Schema::Field
          field = _ = field_for(node.field)

          if field.type.embedded_object?
            requested_fields_under(node, path_prefix: "#{path_prefix}#{field.name_in_index}.")
          else
            field.index_field_names_for_resolution.map do |name|
              "#{path_prefix}#{name}"
            end
          end
        end

        def field_for(field)
          return nil unless field
          @schema.field_named(field.owner.graphql_name, field.name)
        end

        def pagination_fields_need_individual_docs?(lookahead)
          # If the client wants cursors, we need to request docs from the datastore so we get back the sort values
          # for each node, which we can then encode into a cursor.
          return true if lookahead.selection(@schema.element_names.edges).selects?(@schema.element_names.cursor)

          # Most subfields of `page_info` also require us to fetch documents from the datastore. For example,
          # we cannot compute `has_next_page` or `has_previous_page` correctly if we do not fetch a full page
          # of documents from the datastore.
          lookahead.selection(@schema.element_names.page_info).selections.any?
        end

        def relay_connection_node_from(lookahead)
          node = lookahead.selection(@schema.element_names.nodes)
          return node if node.selected?

          lookahead
            .selection(@schema.element_names.edges)
            .selection(@schema.element_names.node)
        end

        # total_hits_count is needed when the connection explicitly specifies `total_edge_count` to
        # be returned in the part of the GraphQL query we are processing. Note that the aggregation
        # query adapter can also set it to true based on its needs.
        def query_needs_total_document_count?(lookahead)
          # If total edge count is explicitly specified in page_info, we have to return the total count
          lookahead.selects?(@schema.element_names.total_edge_count)
        end

        def requesting_all_highlights?(lookahead)
          all_highlights =
            lookahead
              .selection(@schema.element_names.edges)
              .selection(@schema.element_names.all_highlights)

          all_highlights.selects?(@schema.element_names.path) || all_highlights.selects?(@schema.element_names.snippets)
        end

        def graphql_dynamic_field?(node)
          # As per https://spec.graphql.org/October2021/#sec-Objects,
          # > All fields defined within an Object type must not have a name which begins with "__"
          # > (two underscores), as this is used exclusively by GraphQL’s introspection system.
          node.field.name.start_with?("__")
        end
      end
    end
  end
end
