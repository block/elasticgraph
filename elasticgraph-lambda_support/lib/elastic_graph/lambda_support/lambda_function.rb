# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/monotonic_clock"

module ElasticGraph
  module LambdaSupport
    # Mixin that can be used to define a lambda function, with common cross-cutting concerns
    # handled automatically for you:
    #
    #   - The amount of time it takes to boot the lambda is logged.
    #   - An error handling hook is provided which applies both to boot-time logic and request handling.
    #
    # It is designed to be prepending onto a class, like so:
    #
    # class DoSomething
    #   prepend LambdaFunction
    #
    #   def initialize
    #     require 'my_application'
    #     @application = MyApplication.new(ENV[...])
    #   end
    #
    #   def handle_request(event:, context:)
    #     @application.handle_request(event: event, context: context)
    #   end
    # end
    #
    # Using `prepend` is necessary so that it can wrap `initialize` and `handle_request` with error handling.
    # It is recommended that `require`s be put in `initialize` instead of at the top of the lambda function
    # file so that the error handler can handle any errors that happen while loading dependencies.
    #
    # `handle_exceptions` can also be overridden in order to provide error handling.
    module LambdaFunction
      def initialize(output: $stdout, monotonic_clock: Support::MonotonicClock.new)
        handle_exceptions do
          log_duration(output, monotonic_clock, "Booting the lambda function") do
            super()
          end
        end
      end

      def handle_request(event:, context:)
        handle_exceptions { super }
      end

      private

      # By default we just allow exceptions to bubble up. This is provided so that there is an exception handling hook that can be overridden.
      def handle_exceptions
        yield
      end

      def log_duration(output, monotonic_clock, description)
        start_ms = monotonic_clock.now_in_ms
        yield
        stop_ms = monotonic_clock.now_in_ms
        duration_ms = stop_ms - start_ms

        output.puts "#{description} took #{duration_ms} milliseconds."
      end
    end
  end
end
