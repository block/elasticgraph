# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/graphql/query_adapter/requested_fields"
require "elastic_graph/graphql/resolvers/query_source"

module ElasticGraph
  module Apollo
    module GraphQL
      # GraphQL resolver for the Apollo `Query._entities` field. For details on this field, see:
      #
      # https://www.apollographql.com/docs/federation/subgraph-spec/#resolve-requests-for-entities
      #
      # @private
      class EntitiesFieldResolver
        def initialize(elasticgraph_graphql:, config:)
          @datastore_query_builder = elasticgraph_graphql.datastore_query_builder
          @schema_element_names = elasticgraph_graphql.runtime_metadata.schema_element_names
        end

        def resolve(field:, object:, args:, context:, lookahead:)
          schema = context.fetch(:elastic_graph_schema)

          representations = args.fetch("representations").map.with_index do |rep, index|
            try_parse_representation(rep, schema) do |error_description|
              context.add_error(::GraphQL::ExecutionError.new("Representation at index #{index} #{error_description}."))
            end
          end

          representations_by_adapter = representations.group_by { |rep| rep&.adapter }

          # The query attributes that are based on the requested subfields are the same across all representations,
          # so we build the hash of those attributes once here.
          query_attributes = ElasticGraph::GraphQL::QueryAdapter::RequestedFields
            .new(schema)
            .query_attributes_for(field: field, lookahead: lookahead)
            .merge(monotonic_clock_deadline: context[:monotonic_clock_deadline])

          # Build a separate query per adapter instance since each adapter instance is capable of building
          # a single query that handles all representations assigned to it.
          query_by_adapter = representations_by_adapter.to_h do |adapter, reps|
            query = build_query(adapter, reps, query_attributes) if adapter
            [adapter, query]
          end

          responses_by_query = ElasticGraph::GraphQL::Resolvers::QuerySource.execute_many(query_by_adapter.values.compact, for_context: context)
          indexed_search_hits_by_adapter = query_by_adapter.to_h do |adapter, query|
            indexed_search_hits = query ? adapter.index_search_hits(responses_by_query.fetch(query)) : {} # : ::Hash[::String, ElasticGraph::GraphQL::DatastoreResponse::Document]
            [adapter, indexed_search_hits]
          end

          representations.map.with_index do |representation, index|
            next unless (adapter = representation&.adapter)

            indexed_search_hits = indexed_search_hits_by_adapter.fetch(adapter)
            adapter.identify_matching_hit(indexed_search_hits, representation, context: context, index: index)
          end
        end

        private

        # Builds a datastore query for the given specific representation.
        def build_query(adapter, representations, query_attributes)
          return nil unless adapter.indexed?

          type = adapter.type
          query = @datastore_query_builder.new_query(search_index_definitions: type.search_index_definitions, **query_attributes)
          adapter.customize_query(query, representations)
        end

        # Helper method that parses an `_Any` representation of an entity into a `Representation`
        # object that contains the GraphQL `type` and a query `filter`.
        #
        # Based on whether or not this is successful, one of two things will happen:
        #
        # - If we can't parse it, an error description will be yielded and `nil` will be return
        #   (to indicate we couldn't parse it).
        # - If we can parse it, the representation will be returned (and nothing will be yielded).
        def try_parse_representation(representation, schema)
          notify_error = proc do |msg|
            yield msg.to_s
            return nil # returns `nil` from the `try_parse_representation` method.
          end

          unless representation.is_a?(::Hash)
            notify_error.call("is not a JSON object")
          end

          unless (typename = representation["__typename"])
            notify_error.call("lacks a `__typename`")
          end

          type = begin
            schema.type_named(typename)
          rescue ElasticGraph::Errors::NotFoundError
            notify_error.call("has an unrecognized `__typename`: #{typename}")
          end

          if (fields = representation.except("__typename")).empty?
            notify_error.call("has only a `__typename` field")
          end

          if !type.indexed_document?
            RepresentationWithoutIndex.new(
              type: type,
              representation_hash: representation
            )
          elsif (id = fields["id"])
            RepresentationWithId.new(
              type: type,
              id: id,
              other_fields: translate_field_names(fields.except("id"), type),
              schema_element_names: @schema_element_names
            )
          else
            RepresentationWithoutId.new(
              type: type,
              fields: translate_field_names(fields, type),
              schema_element_names: @schema_element_names
            )
          end
        end

        def translate_field_names(fields_hash, type)
          fields_hash.to_h do |public_field_name, value|
            field = type.field_named(public_field_name)
            field_name = field.name_in_index.to_s

            case value
            when ::Hash
              [field_name, translate_field_names(value, field.type.unwrap_fully)]
            else
              # TODO: Add support for array cases (e.g. when value is an array of hashes).
              [field_name, value]
            end
          end
        end

        # A simple value object containing a parsed form of an `_Any` representation when there's an `id` field.
        #
        # @private
        class RepresentationWithId < ::Data.define(:type, :id, :other_fields, :schema_element_names, :adapter)
          def initialize(type:, id:, other_fields:, schema_element_names:)
            super(
              type: type, id: id, other_fields: other_fields, schema_element_names: schema_element_names,
              # All `RepresentationWithId` instances with the same `type` can be handled by the same adapter,
              # since we can combine them into a single query filtering on `id`.
              adapter: Adapter.new(type, schema_element_names)
            )
          end

          Adapter = ::Data.define(:type, :schema_element_names) do
            # @implements Adapter

            def customize_query(query, representations)
              # Given a set of representations, builds a filter that will match all of them (and only them).
              all_ids = representations.map(&:id).reject { |id| id.is_a?(::Array) or id.is_a?(::Hash) }
              filter = {"id" => {schema_element_names.equal_to_any_of => all_ids}}

              query.merge_with(
                document_pagination: {first: representations.length},
                requested_fields: additional_requested_fields_for(representations),
                filters: [filter]
              )
            end

            # Given a query response, indexes the search hits for easy `O(1)` retrieval by `identify_matching_hit`.
            # This allows us to provide `O(N)` complexity in our resolver instead of `O(N^2)`.
            def index_search_hits(response)
              response.to_h { |hit| [hit.id, hit] }
            end

            # Given some indexed search hits and a representation, identifies the search hit that matches the representation.
            def identify_matching_hit(indexed_search_hits, representation, context:, index:)
              hit = indexed_search_hits[representation.id]
              hit if hit && match?(representation.other_fields, hit.payload)
            end

            def indexed?
              true
            end

            private

            def additional_requested_fields_for(representations)
              representations.flat_map do |representation|
                fields_in(representation.other_fields)
              end
            end

            def fields_in(hash)
              hash.flat_map do |field_name, value|
                case value
                when ::Hash
                  fields_in(value).map do |sub_field_name|
                    "#{field_name}.#{sub_field_name}"
                  end
                else
                  # TODO: Add support for array cases.
                  [field_name]
                end
              end
            end

            def match?(expected, actual)
              expected.all? do |key, value|
                case value
                when ::Hash
                  match?(value, actual[key])
                when ::Array
                  # TODO: Add support for array filtering, instead of ignoring it.
                  true
                else
                  value == actual[key]
                end
              end
            end
          end
        end

        # A simple value object containing a parsed form of an `_Any` representation when there's no `id` field.
        #
        # @private
        class RepresentationWithoutId < ::Data.define(:type, :fields, :schema_element_names)
          # @dynamic type

          # Each `RepresentationWithoutId` instance needs to be handled by a separate adapter. We can't
          # safely combine representations into a single datastore query, so we want each to handled
          # by a separate adapter instance. So, we use the representation itself as the adapter.
          def adapter
            self
          end

          def customize_query(query, representations)
            query.merge_with(
              # In the case of representations which don't query Id, we ask for 2 documents so that
              # if something weird is going on and it matches more than 1, we can detect that and return an error.
              document_pagination: {first: 2},
              filters: [build_filter_for_hash(fields)]
            )
          end

          def index_search_hits(response)
            {"search_hits" => response.to_a}
          end

          def identify_matching_hit(indexed_search_hits, representation, context:, index:)
            search_hits = indexed_search_hits.fetch("search_hits")
            if search_hits.size > 1
              context.add_error(::GraphQL::ExecutionError.new("Representation at index #{index} matches more than one entity."))
              nil
            else
              search_hits.first
            end
          end

          def indexed?
            true
          end

          private

          def build_filter_for_hash(fields)
            # We must exclude `Array` values because we'll get an exception from the datastore if we allow it here.
            # Filtering it out just means that the representation will not match an entity.
            fields.reject { |key, value| value.is_a?(::Array) }.transform_values do |value|
              if value.is_a?(::Hash)
                build_filter_for_hash(value)
              else
                {schema_element_names.equal_to_any_of => [value]}
              end
            end
          end
        end

        # @private
        class RepresentationWithoutIndex < ::Data.define(:type, :representation_hash)
          # @dynamic type
          def adapter
            self
          end

          # :nocov: -- these methods are not called on an adapter when `indexed?` returns `false`.
          def customize_query(query, representations)
            nil
          end

          def index_search_hits(response)
            nil
          end
          # :nocov:

          def identify_matching_hit(indexed_search_hits, representation, context:, index:)
            representation.representation_hash
          end

          def indexed?
            false
          end
        end
      end
    end
  end
end
