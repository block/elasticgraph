# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/event_id"

module ElasticGraph
  class Indexer
    module Operation
      # Describes the result of an operation.
      # :category value will be one of: [:success, :noop, :failure]
      Result = ::Data.define(:category, :operation, :description) do
        # @implements Result
        def self.success_of(operation)
          Result.new(
            category: :success,
            operation: operation,
            description: nil
          )
        end

        def self.noop_of(operation, description)
          Result.new(
            category: :noop,
            operation: operation,
            description: description
          )
        end

        def self.failure_of(operation, description)
          Result.new(
            category: :failure,
            operation: operation,
            description: description
          )
        end

        def operation_type
          operation.type
        end

        def event
          operation.event
        end

        def event_id
          EventID.from_event(event)
        end

        def summary
          # :nocov: -- `description == nil` case is not covered; not simple to test.
          suffix = description ? "--#{description}" : nil
          # :nocov:
          "<#{operation.description} #{event_id} #{category}#{suffix}>"
        end

        def inspect
          parts = [
            self.class.name,
            operation_type.inspect,
            category.inspect,
            event_id,
            description
          ].compact

          "#<#{parts.join(" ")}>"
        end
        alias_method :to_s, :inspect
      end
    end
  end
end
