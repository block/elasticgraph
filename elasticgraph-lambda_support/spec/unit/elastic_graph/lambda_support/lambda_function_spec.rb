# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/lambda_support/lambda_function"
require "stringio"

module ElasticGraph
  module LambdaSupport
    RSpec.describe LambdaFunction do
      let(:output) { StringIO.new }
      let(:monotonic_clock) { instance_double(Support::MonotonicClock, now_in_ms: 100) }

      it "calls `initialize` and `handle_request` at the expected times" do
        lambda_function = new_lambda_function do
          def initialize
            @boot_state ||= []
            @boot_state << "booted"
          end

          def handle_request(event:, context:)
            {
              event: event,
              context: context,
              boot_state: @boot_state
            }
          end
        end

        response = lambda_function.handle_request(event: :my_event1, context: :my_context1)
        expect(response).to eq({
          event: :my_event1,
          context: :my_context1,
          boot_state: ["booted"]
        })

        response = lambda_function.handle_request(event: :my_event2, context: :my_context2)
        expect(response).to eq({
          event: :my_event2,
          context: :my_context2,
          boot_state: ["booted"] # verify that boot_state hasn't grown (since on_boot should not be called on every request)
        })
      end

      it "allows the `handle_exceptions` hook to be overridden to handle boot-time errors" do
        handled_errors = []

        error_handler = Module.new do
          define_method :handle_exceptions do |&block|
            block.call
          rescue => e
            handled_errors << [e.class, e.message]
          end
        end

        new_lambda_function do
          prepend error_handler

          def initialize
            raise "Something went wrong during boot"
          end
        end

        expect(handled_errors).to eq [
          [RuntimeError, "Something went wrong during boot"]
        ]
      end

      it "allows the `handle_exceptions` hook to be overridden to handle request-time errors" do
        handled_errors = []

        error_handler = Module.new do
          define_method :handle_exceptions do |&block|
            block.call
          rescue => e
            handled_errors << [e.class, e.message]
          end
        end

        lambda_function = new_lambda_function do
          prepend error_handler

          def handle_request(event:, context:)
            raise "Invalid event: #{event}"
          end
        end

        lambda_function.handle_request(event: :some_event, context: :some_context)

        expect(handled_errors).to eq [
          [RuntimeError, "Invalid event: some_event"]
        ]
      end

      it "logs how long the lambda function takes to boot" do
        now_in_ms = 250
        allow(monotonic_clock).to receive(:now_in_ms) { now_in_ms }

        new_lambda_function do
          define_method :initialize do
            now_in_ms = 500
          end

          def handle_request(event:, context:)
          end
        end

        expect(output.string).to include("Booting the lambda function took 250 milliseconds.")
      end

      def new_lambda_function(&definition)
        klass = ::Class.new do
          prepend LambdaFunction
          class_exec(&definition)
        end

        klass.new(output: output, monotonic_clock: monotonic_clock)
      end
    end
  end
end
