# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/resolvable_value"

module ElasticGraph
  class GraphQL
    module Resolvers
      module RelayConnection
        # Provides the `PageInfo` field values required by the relay spec.
        #
        # The relay connections spec defines an algorithm behind `hasPreviousPage` and `hasNextPage`:
        # https://facebook.github.io/relay/graphql/connections.htm#sec-undefined.PageInfo.Fields
        #
        # However, it has a couple bugs as currently written (https://github.com/facebook/relay/issues/2787),
        # so we have implemented our own algorithm instead. It would be nice to calculate `hasPreviousPage`
        # and `hasNextPage` on-demand in a resolver, so we do not spend any effort on it if the client has
        # not requested those fields, but it is quite hard to calculate them after the fact: we need to know
        # whether we removed any leading or trailing items while processing the list to accurately answer
        # the question, "do we have a page before or after the one we are returning?".
        #
        # Note: it's not clear what values `hasPreviousPage` and `hasNextPage` should have when we are returning
        # a blank page (the client isn't being returned any cursors to continue paginating from!). This logic,
        # as written, will normally cause both fields to be `true` (our request of `size: size + 1` will get us
        # a list of 1 document, which will then be removed, causing `items.first` and `items.last` to
        # both change to `nil`). However, if the datastore returns an empty list to us than `false` will be returned
        # for one or both fields, based on the presence or absence of the `before`/`after` cursors in the pagination
        # arguments. Regardless, given that it's not clear what the correct value is, we are just doing the
        # least-effort thing and not putting any special handling for this case in place.
        class PageInfo < ResolvableValue.new(
          # The array of nodes for this page before we applied necessary truncation.
          :before_truncation_nodes,
          # The array of edges for this page.
          :edges,
          # The paginator built from the field arguments.
          :paginator
        )
          # @dynamic initialize, with, before_truncation_nodes, edges, paginator

          def start_cursor
            edges.first&.cursor
          end

          def end_cursor
            edges.last&.cursor
          end

          def has_previous_page
            # If we dropped the first node during truncation then it means we removed some leading docs, indicating a previous page.
            return true if edges.first&.node != before_truncation_nodes.first

            # Nothing exists both before and after the same cursor, and there is therefore no page before that set of results.
            return false if paginator.before == paginator.after

            # If an `after` cursor was passed then there is definitely at least one doc before the page we are
            # returning (the one matching the cursor), assuming the client did not construct a cursor by hand
            # (which we do not support).
            !!paginator.after
          end

          def has_next_page
            # If we dropped the last node during truncation then it means we removed some trailing docs, indicating a next page.
            return true if edges.last&.node != before_truncation_nodes.last

            # Nothing exists both before and after the same cursor, and there is therefore no page after that set of results.
            return false if paginator.before == paginator.after

            # If a `before` cursor was passed then there is definitely at least one doc after the page we are
            # returning (the one matching the cursor), assuming the client did not construct a cursor by hand
            # (which we do not support).
            !!paginator.before
          end
        end
      end
    end
  end
end
