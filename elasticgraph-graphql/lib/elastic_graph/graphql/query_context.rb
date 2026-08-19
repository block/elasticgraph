# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/graphql/client"
require "elastic_graph/graphql/lookahead_errors"
require "elastic_graph/graphql/query_details_tracker"
require "graphql"

module ElasticGraph
  class GraphQL
    # `GraphQL::Query::Context` subclass used by ElasticGraph, providing typed accessors in
    # place of untyped context hash keys. Registered as the `context_class` on the `GraphQL::Schema`
    # built by `Schema`, via `new_class`, so that every query gets an instance closed over the
    # `Schema` and `DatastoreSearchRouter` in use for that schema.
    class QueryContext < ::GraphQL::Query::Context
      def self.elastic_graph_schema
        @elastic_graph_schema
      end

      def self.datastore_search_router
        @datastore_search_router
      end

      # Builds a `QueryContext` subclass closed over the given `elastic_graph_schema` and
      # `datastore_search_router`, suitable for registering as a `GraphQL::Schema#context_class`.
      def self.new_class(elastic_graph_schema:, datastore_search_router:)
        klass = ::Class.new(self) # : singleton(QueryContext)
        klass.instance_variable_set(:@elastic_graph_schema, elastic_graph_schema)
        klass.instance_variable_set(:@datastore_search_router, datastore_search_router)
        klass
      end

      # `elastic_graph_schema` is only `nil` before `new_class` has closed over it, which never
      # happens for a `QueryContext` actually used to execute a query (see `Schema#initialize`).
      def elastic_graph_schema
        self.class.elastic_graph_schema # : Schema
      end

      def datastore_search_router
        self.class.datastore_search_router # : DatastoreSearchRouter
      end

      # @dynamic monotonic_clock_deadline, elastic_graph_client, http_request
      attr_reader :monotonic_clock_deadline, :elastic_graph_client, :http_request

      # Registers the given ElasticGraph-managed values on this context. Intended to be called
      # exactly once, by `Schema#new_graphql_query` callers immediately after building a query and
      # before making it available to resolvers or other user-facing code. Not for use elsewhere.
      def register_elastic_graph_values(monotonic_clock_deadline: nil, elastic_graph_client: Client::ANONYMOUS, http_request: nil)
        @monotonic_clock_deadline = monotonic_clock_deadline
        @elastic_graph_client = elastic_graph_client
        @http_request = http_request
      end

      # Lazily builds (and memoizes) the `QueryDetailsTracker` for this query.
      def elastic_graph_query_tracker
        @elastic_graph_query_tracker ||= QueryDetailsTracker.empty
      end

      # Caches the result of the given block (a built `DatastoreQuery`) under `cache_key`, scoped to
      # this single query execution. See `Resolvers::QueryAdapter#build_query_from` for why this
      # memoization is beneficial.
      def cache_datastore_query(cache_key)
        datastore_query_cache[cache_key] ||= yield
      end

      # These context hash keys were replaced by typed accessors above. `[]`/`fetch` raise a
      # helpful error here instead of silently returning `nil`, in case any custom resolver code
      # still reads them as hash keys.
      REMOVED_KEY_REPLACEMENTS = {
        elastic_graph_schema: "elastic_graph_schema",
        datastore_search_router: "datastore_search_router",
        datastore_query_cache: "cache_datastore_query",
        elastic_graph_query_tracker: "elastic_graph_query_tracker",
        monotonic_clock_deadline: "monotonic_clock_deadline",
        elastic_graph_client: "elastic_graph_client",
        http_request: "http_request"
      }

      def [](key)
        raise_if_removed_key(key)
        super
      end

      def fetch(key, *args, &block)
        raise_if_removed_key(key)
        super
      end

      # Records that `node`, a `GraphQL::Execution::Lookahead` node at or beneath the field currently
      # being resolved, is invalid, with the given `message`. Intended for a custom lookahead-driven
      # resolver that discovers a problem with itself or a *descendant* field while building its
      # datastore query, and cannot raise a `GraphQL::ExecutionError` for it there (doing so would
      # fail this resolver's entire subtree instead of just the one bad field).
      #
      # `extensions`, if provided, is included verbatim under the `"extensions"` key of the error
      # in the GraphQL response; when omitted, no `"extensions"` key is added.
      #
      # `node` is resolved into a matching field the next time GraphQL execution reaches it: instead
      # of running the registered resolver, ElasticGraph fails that field with a
      # `GraphQL::ExecutionError` built from `message`/`extensions`, without disrupting sibling
      # fields. A resolver that flags *itself* can report the error by returning
      # `#matching_lookahead_error`, giving it one consistent way to fail a field regardless of
      # whether the problem is with itself or a descendant.
      #
      # Must be called while the recording field is being resolved, since `node` is resolved to a
      # response path relative to `#current_path`. Raises `Errors::ConfigError` if `node` is not
      # selected at or beneath that path.
      def record_lookahead_error(node, message, extensions: nil)
        current_path = self.current_path # : Array[String | Integer]
        (@lookahead_errors ||= LookaheadErrors.new).record(node, message, root_lookahead: query.lookahead, recording_path: current_path, extensions: extensions)
      end

      # Returns a `GraphQL::ExecutionError` for the field about to be resolved (at `#current_path`)
      # if an ancestor resolver recorded a lookahead error matching it, or `nil` otherwise.
      def matching_lookahead_error
        # Checked on every field resolution, so the overwhelmingly common case--no lookahead error
        # ever recorded for this query--must stay cheap: return before building `#current_path`
        # (which allocates) or a `LookaheadErrors` (which `#record_lookahead_error` never got called
        # to create).
        return nil unless (lookahead_errors = @lookahead_errors)
        current_path = self.current_path # : Array[String | Integer]
        lookahead_errors.matching_error_for(current_path)
      end

      private

      def raise_if_removed_key(key)
        if (replacement = REMOVED_KEY_REPLACEMENTS[key])
          raise Errors::ConfigError, "`context[#{key.inspect}]` is no longer supported; use `context.#{replacement}` instead."
        end
      end

      def datastore_query_cache
        @datastore_query_cache ||= {}
      end
    end
  end
end
