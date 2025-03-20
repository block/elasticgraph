# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/logger"
require "stringio"

module LogCaptureSupport
  def log_device
    @log_device ||= StringIO.new
  end

  def logger
    @logger ||= begin
      original_formatter = ElasticGraph::Support::Logger::JSONAwareFormatter.new
      ElasticGraph::Support::Logger::Factory.build(
        device: log_device,
        config: ElasticGraph::Support::Logger::Config.new(
          device: "stdout", # ignored given `device:` above, but required to be set
          level: "INFO",
          formatter: ->(*args, msg) do
            # Don't log VCR UnhandledHTTPRequestErrors. The `GraphQL::QueryExecutor` logs any
            # exceptions that happen during query execution, and this exception will happen if
            # the recorded VCR cassette differs from the datastore requests being made.
            #
            # Our VCR support will automatically retry the test when it hits this error after deleting
            # the VCR cassette. However, since we also assert that there are no logged warnings in
            # many tests, if we allow the VCR errors to get written to our logs, tests can fail
            # non-deterministically. So here we exclude them from our logs.
            # :nocov: -- the `unless` branch isn't usually covered.
            original_formatter.call(*args, msg) unless msg.include?("VCR::Errors::UnhandledHTTPRequestError")
            # :nocov:
          end
        )
      )
    end
  end

  # this method must be prepended so that we can force `log_device` so
  # that any call to `build_datastore_core` in groups tagged with `:capture_logs
  # uses our configured log device.
  def build_datastore_core(**options, &block)
    super(logger: logger, **options, &block)
  end

  def logged_output
    log_device.string
  end

  def logged_jsons
    logged_messages.select.filter_map do |log_message|
      if log_message.lines.one? && /{".+}\s*$/.match?(log_message)
        ::JSON.parse(log_message[log_message.index("{")..])
      end
    end
  end

  def logged_jsons_of_type(message_type)
    logged_jsons.select { |json| json["message_type"] == message_type }
  end

  def logged_warnings
    # Ruby's standard log format starts each message with a level indicator:
    # https://docs.ruby-lang.org/en/master/Logger.html#class-Logger-label-Log+Level
    # e.g. "I, ..." for info, `W, ..." for warn, etc.
    # Here we want to only consider messages that are warning level or more severe.
    # W=WARN, E=ERROR, F=FATAL, A=UNKNOWN
    logged_messages.select do |message|
      message.start_with?("W, ", "E, ", "F, ", "A, ")
    end
  end

  def log(string_regex_or_matcher)
    @expect_logging = true
    change { logged_output }.to(string_regex_or_matcher)
  end

  def log_warning(string_regex_or_matcher)
    @expect_logging = true
    change { logged_warnings.join }.to(string_regex_or_matcher)
  end

  def avoid_logging_warnings
    maintain { logged_warnings }
  end

  def expect_logging?
    !!@expect_logging
  end

  def flush_logs
    log_device.truncate(0)
    log_device.rewind
  end

  def logged_messages
    # Ruby's standard log format starts each message with a level indicator:
    # https://docs.ruby-lang.org/en/master/Logger.html#class-Logger-label-Log+Level
    # e.g. "I, ..." for info, `W, ..." for warn, etc.
    logged_output.split(/(?=^[DIWEFA], )/)
  end
end

RSpec.configure do |c|
  c.prepend LogCaptureSupport, :capture_logs

  # For any example where we are capturing logging, add an automatic assertion
  # that no logging occurred (as that indicates a warning of some problem, generally),
  # unless the example specifically expected logging, via the use of the `log` matcher
  # defined above.
  c.around(:example, :capture_logs) do |ex|
    if ex.metadata[:expect_warning_logging]
      ex.run
    else
      expect(&ex).to avoid_logging_warnings.or change { ex.example.example_group_instance.expect_logging? }.to(true)
    end
  end
end
