# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "json"
require "logger"
require "pathname"

module ElasticGraph
  module Support
    # @private
    module Logger
      # Builds a logger instance from the given parsed YAML config.
      def self.from_parsed_yaml(parsed_yaml)
        Factory.build(config: Config.from_parsed_yaml(parsed_yaml))
      end

      # @private
      module Factory
        def self.build(config:, device: nil)
          ::Logger.new(
            device || config.prepared_device,
            level: config.level,
            formatter: config.formatter
          )
        end
      end

      # @private
      class JSONAwareFormatter
        def initialize
          @original_formatter = ::Logger::Formatter.new
        end

        def call(severity, datetime, progname, msg)
          msg = msg.is_a?(::Hash) ? ::JSON.generate(msg, space: " ") : msg
          @original_formatter.call(severity, datetime, progname, msg)
        end
      end

      # @private
      class Config < ::Data.define(
        # Determines what severity level we log. Valid values are `DEBUG`, `INFO`, `WARN`,
        # `ERROR`, `FATAL` and `UNKNOWN`.
        :level,
        # Determines where we log to. Must be a string. "stdout" or "stderr" are interpreted
        # as being those output streams; any other value is assumed to be a file path.
        :device,
        # Object used to format log messages. Defaults to an instance of `JSONAwareFormatter`.
        :formatter
      )
        def prepared_device
          case device
          when "stdout" then $stdout
          when "stderr" then $stderr
          else
            ::Pathname.new(device).parent.mkpath
            device
          end
        end

        def self.from_parsed_yaml(hash)
          hash = hash.fetch("logger")
          extra_keys = hash.keys - EXPECTED_KEYS

          unless extra_keys.empty?
            raise Errors::ConfigError, "Unknown `logger` config settings: #{extra_keys.join(", ")}"
          end

          new(
            level: hash["level"] || "INFO",
            device: hash.fetch("device"),
            formatter: ::Object.const_get(hash.fetch("formatter", JSONAwareFormatter.name)).new
          )
        end

        EXPECTED_KEYS = members.map(&:to_s)
      end
    end
  end
end
