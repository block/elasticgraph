# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/test_support/converters"

module ElasticGraph
  module Local
    # Responsible for coordinating the generation and indexing of fake data batches.
    # Designed to be pluggable with different publishing strategies.
    #
    # @private
    class IndexingCoordinator
      PARALLELISM = 8

      def initialize(fake_data_batch_generator, output: $stdout, &publish_batch)
        @fake_data_batch_generator = fake_data_batch_generator
        @publish_batch = publish_batch
        @output = output
      end

      def index_fake_data(num_batches)
        batch_queue = ::Thread::Queue.new

        publishing_threads = Array.new(PARALLELISM) { new_publishing_thread(batch_queue) }

        num_batches.times do
          batch = @fake_data_batch_generator.call
          @output.puts "Generated batch of #{batch.size} documents..."
          batch_queue << batch
        end

        publishing_threads.map { batch_queue << :done }
        publishing_threads.each(&:join)

        @output.puts "...done."
      end

      private

      def new_publishing_thread(batch_queue)
        ::Thread.new do
          loop do
            batch = batch_queue.pop
            break if batch == :done
            @publish_batch.call(ElasticGraph::Indexer::TestSupport::Converters.upsert_events_for_records(batch))
            @output.puts "Published batch of #{batch.size} documents..."
          end
        end
      end
    end
  end
end
