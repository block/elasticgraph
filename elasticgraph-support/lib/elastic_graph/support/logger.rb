# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/config"
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
        Factory.build(config: Config.from_parsed_yaml(parsed_yaml) || Config.new)
      end

      # @private
      class Config < Support::Config.define(:level, :device, :formatter)
        # @dynamic self.from_parsed_yaml

        json_schema at: "logger",
          optional: false,
          description: "Configuration for logging used by all parts of ElasticGraph.",
          properties: {
            level: {
              description: "Determines what severity level we log.",
              examples: %w[INFO WARN],
              enum: %w[DEBUG debug INFO info WARN warn ERROR error FATAL fatal UNKNOWN unknown],
              default: "INFO"
            },
            device: {
              description: 'Determines where we log to. "stdout" or "stderr" are interpreted ' \
                "as being those output streams; any other value is assumed to be a file path.",
              examples: %w[stdout logs/development.log],
              default: "stdout",
              type: "string",
              minLength: 1
            },
            formatter: {
              description: "Class used to format log messages.",
              examples: %w[ElasticGraph::Support::Logger::JSONAwareFormatter MyAlternateFormatter],
              type: "string",
              pattern: /^[A-Z]\w+(::[A-Z]\w+)*$/.source, # https://rubular.com/r/UuqAz4fR3kdMip
              default: "ElasticGraph::Support::Logger::JSONAwareFormatter"
            }
          }

        def prepared_device
          case device
          when "stdout" then $stdout
          when "stderr" then $stderr
          else
            ::Pathname.new(device).parent.mkpath
            device
          end
        end

        private

        def convert_values(formatter:, level:, device:)
          formatter = ::Object.const_get(formatter).new
          {formatter: formatter, level: level, device: device}
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
      module Factory
        def self.build(config:, device: nil)
          ::Logger.new(
            device || config.prepared_device,
            level: config.level,
            formatter: config.formatter
          )
        end
      end
    end
  end
end
