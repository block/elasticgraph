# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  class Indexer
    class IndexingFailuresError < Errors::Error
      # Builds an `IndexingFailuresError` with a nicely formatted message for the given array of failures.
      # Each failure must respond to `message` and `message_id` (see `FailedEventError`).
      def self.for(failures:, event_count:)
        summary = "Got #{failures.size} failure(s) from #{event_count} event(s):"
        failure_details = failures.map.with_index { |failure, index| "#{index + 1}) #{failure.message}" }

        message_ids = failures.filter_map(&:message_id).uniq
        if message_ids.any?
          message_details = "These failures came from #{message_ids.size} message(s): #{message_ids.join(", ")}."
        end

        new([summary, failure_details, message_details].compact.join("\n\n"))
      end
    end
  end
end
