# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "graphql"

module ElasticGraph
  class GraphQL
    # Tracks "lookahead errors": errors that an ancestor resolver discovers about a *descendant*
    # field while walking its lookahead to build a datastore query, but cannot raise for (raising
    # there would fail the ancestor's entire subtree instead of just the one bad descendant).
    #
    # See `docs/adr/0001-lookahead-error-record-key.md` for the design rationale behind the
    # record key used here.
    class LookaheadErrors
      # A recorded error about the field selected at `path`--an absolute response path from the root
      # of the query, with no list indices.
      Record = ::Data.define(:path, :message, :extensions) do
        # @implements Record

        # Indices are skipped rather than compared because the flagged node's list positions don't
        # exist yet when it is recorded, so one record can match many response positions (e.g. every
        # bucket of an aggregation).
        def matches?(current_path)
          current_path.grep_v(::Integer) == path
        end
      end

      def initialize
        @records = [] # : Array[Record]
      end

      # Records that `node` (a lookahead node at or beneath the field being resolved at
      # `recording_path`) is invalid, with the given `message`, making it matchable via
      # `#matching_error_for`. `root_lookahead` is the lookahead of the query as a whole, which we
      # walk to resolve `node` to its absolute path.
      def record(node, message, root_lookahead:, recording_path:, extensions: nil)
        # A node reached through a fragment spread that's used in multiple places has multiple paths;
        # only the one(s) under the field being resolved are ours to flag.
        prefix = recording_path.grep_v(::Integer)
        target_ast_nodes = node.selected? ? node.ast_nodes.to_set : ::Set.new # : ::Set[::GraphQL::Language::Nodes::Field]
        paths = find_paths(root_lookahead, target_ast_nodes, []).select { |path| path.first(prefix.size) == prefix }

        if paths.empty?
          raise Errors::ConfigError, "`record_lookahead_error` was given a lookahead node that is not " \
            "selected at or beneath #{prefix.inspect}, the field being resolved. Note that " \
            "`Lookahead#selection` returns a null object for an unselected (or misspelled) field."
        end

        @records.concat(paths.map { |path| Record.new(path: path, message: message, extensions: extensions) })
      end

      # Returns a `GraphQL::ExecutionError` for the first recorded error matching `current_path` (the
      # path of the field about to be resolved), or `nil` if none match. Cheap (an `Array#find` over
      # `@records`, empty for the overwhelmingly common query that never records a lookahead error)
      # with no separate guard needed at call sites. A record legitimately matches nothing at all when
      # execution never reaches the flagged position (e.g. its parent resolved to an empty list).
      def matching_error_for(current_path)
        record = @records.find { |r| r.matches?(current_path) }
        return nil unless record

        ::GraphQL::ExecutionError.new(record.message, extensions: record.extensions)
      end

      private

      # Finds the index-free response-key path(s) from `current` down to a node whose `ast_nodes`
      # intersect `target_ast_nodes`, including `current` itself (so a node can flag its own
      # recording field, yielding that field's own path).
      def find_paths(current, target_ast_nodes, path_so_far)
        return [path_so_far] if current.ast_nodes.to_set.intersect?(target_ast_nodes)

        current.selections.flat_map do |child|
          # `Lookahead#name` returns the field's method name, not its response key, so aliased
          # selections would collide under it. `#selections` already groups by response key
          # (`alias || name`), so pull the response key straight off the underlying AST node.
          first_ast_node = child.ast_nodes.first
          response_key = first_ast_node.alias || first_ast_node.name
          find_paths(child, target_ast_nodes, path_so_far + [response_key])
        end
      end
    end
  end
end
