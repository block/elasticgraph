# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module QueryRegistry
    ClientData = ::Data.define(:queries_by_original_string, :queries_by_last_string, :canonical_query_strings, :operation_names, :schema_element_names) do
      # @implements ClientData
      def self.from(schema, registered_query_strings)
        queries_by_original_string = registered_query_strings.to_h do |query_string|
          [query_string, ::GraphQL::Query.new(schema.graphql_schema, query_string, validate: false)]
        end

        canonical_query_strings = queries_by_original_string.values.map do |q|
          canonical_query_string_from(q, schema_element_names: schema.element_names)
        end.to_set

        operation_names = queries_by_original_string.values.flat_map { |q| q.operations.keys }.to_set

        new(
          queries_by_original_string: queries_by_original_string,
          queries_by_last_string: {},
          canonical_query_strings: canonical_query_strings,
          operation_names: operation_names,
          schema_element_names: schema.element_names
        )
      end

      def cached_query_for(query_string)
        queries_by_original_string[query_string] || queries_by_last_string[query_string]
      end

      def with_updated_last_query(query_string, query)
        canonical_string = canonical_query_string_from(query)

        # We normally expect to only see one alternate query form from a client. However, a misbehaving
        # client could send us a slightly different query string on each request (imagine if the query
        # had a dynamically generated comment with a timestamp). Here we guard against that case by
        # pruning out the previous hash entry that resolves to the same registered query, ensuring
        # we only cache the most recently seen query string. Note that this operation is unfortunately
        # O(N) instead of O(1) but we expect this operation to happen rarely (and we don't expect many
        # entries in the `queries_by_last_string` hash). We could maintain a 2nd parallel data structure
        # allowing an `O(1)` lookup here but I'd rather not introduce that added complexity for marginal
        # benefit.
        updated_queries_by_last_string = queries_by_last_string.reject do |_, cached_query|
          canonical_query_string_from(cached_query) == canonical_string
        end.merge(query_string => query)

        with(queries_by_last_string: updated_queries_by_last_string)
      end

      def unregistered_query_error_for(query, client)
        if operation_names.include?(query.operation_name.to_s)
          "Query #{fingerprint_for(query)} differs from the registered form of `#{query.operation_name}` " \
          "for client #{client.description}."
        else
          "Query #{fingerprint_for(query)} is unregistered; client #{client.description} has no " \
          "registered query with a `#{query.operation_name}` operation."
        end
      end

      private

      def fingerprint_for(query)
        # `query.fingerprint` raises an error if the query string is nil:
        # https://github.com/rmosolgo/graphql-ruby/issues/4942
        query.query_string ? query.fingerprint : "(no query string)"
      end

      def canonical_query_string_from(query)
        ClientData.canonical_query_string_from(query, schema_element_names: schema_element_names)
      end

      def self.canonical_query_string_from(query, schema_element_names:)
        return "" unless (document = query.document)

        canonicalized_definitions = document.definitions.map do |definition|
          if definition.directives.empty?
            definition
          else
            # Ignore the `@egLatencySlo` directive if it is present. We want to allow it to be included (or not)
            # and potentially have different values from the registered query so that clients don't have to register
            # a new version of their query just to change the latency SLO value.
            #
            # Note: we don't ignore _all_ directives here because other directives might cause significant behavioral
            # changes that should be enforced by the registry query approval process.
            directives = definition.directives.reject do |dir|
              dir.name == schema_element_names.eg_latency_slo
            end

            definition.merge(directives: directives)
          end
        end

        document.merge(definitions: canonicalized_definitions).to_query_string
      end
    end
  end
end
