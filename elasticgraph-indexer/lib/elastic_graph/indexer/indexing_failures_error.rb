# Copyright 2024 - 2025 Block, Inc.
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
      # Builds an `IndexingFailuresError` with a nicely formatted message for the given array of `FailedEventError`.
      def self.for(failures:, events:)
        summary = "Got #{failures.size} failure(s) from #{events.size} event(s):"
        failure_details = failures.map.with_index { |failure, index| "#{index + 1}) #{failure.message}" }

        message_ids = failures.filter_map { |f| f.event["message_id"] }.uniq
        if message_ids.any?
          message_details = "These failures came from #{message_ids.size} message(s): #{message_ids.join(", ")}."
        end

        new([summary, failure_details, message_details].compact.join("\n\n"))
      end
    end
  end
end
