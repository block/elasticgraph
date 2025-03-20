# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/logger"
require "stringio"

module ElasticGraph
  module Support
    module Logger
      RSpec.describe Logger, ".from_parsed_yaml" do
        it "builds a logger instance from a parsed config file" do
          logger = Logger.from_parsed_yaml(parsed_test_settings_yaml)

          expect(logger).to be_a(::Logger)
        end
      end

      RSpec.describe Factory, ".build" do
        it "respects the configured log level" do
          log_io = StringIO.new

          logger = build_logger(device: log_io, config: {"level" => "WARN"})
          logger.info "Some info"
          logger.warn "Some warning"
          logger.error "Some error"

          expect(log_io.string).to include("Some warning", "Some error").and exclude("Some info")
        end

        it "can log any arbitrary string" do
          log_io = StringIO.new
          logger = build_logger(device: log_io)

          logger.info "some string"
          expect(log_io.string.strip).to end_with("some string")
        end

        it "logs the message as JSON when given a hash of metadata" do
          log_io = StringIO.new
          logger = build_logger(device: log_io)

          logger.info("some" => "metadata", "foobar" => 12)
          expect(log_io.string.strip).to end_with("{\"some\": \"metadata\",\"foobar\": 12}")
        end

        it "logs to `stdout` when so configured" do
          expect {
            build_logger(config: {"device" => "stdout"}).info "some log message"
          }.to output(a_string_including("some log message")).to_stdout
        end

        it "logs to `stderr` when so configured" do
          expect {
            build_logger(config: {"device" => "stderr"}).info "some log message"
          }.to output(a_string_including("some log message")).to_stderr
        end

        it "lets a formatter be configured (which can do things like ignore messages)" do
          log_io = StringIO.new
          original_formatter = ::Logger::Formatter.new
          formatter = ->(*args, msg) do
            original_formatter.call(*args, msg) unless msg.include?("password")
          end

          config = Config.new(device: nil, level: :info, formatter: formatter)
          logger = Factory.build(device: log_io, config: config)

          logger.info "username: guest"
          logger.info "password: s3cr3t"

          expect(log_io.string).to include("username: guest").and exclude("password", "s3cr3t")
        end

        context "when `config.device` is set to a file nested in a directory", :in_temp_dir do
          it 'creates the directory so we do not get a "No such file or directory" error' do
            dir = "some_new_dir"

            expect {
              build_logger(config: {"device" => "#{dir}/eg.log"}).info "message"
            }.to change { Dir.exist?(dir) }.from(false).to(true)
          end
        end

        it "raises an error when given an unrecognized config setting" do
          expect {
            build_logger(config: {"fake_setting" => 23})
          }.to raise_error Errors::ConfigError, a_string_including("fake_setting")
        end

        def build_logger(device: nil, config: {}, **options)
          logger_config = {"device" => "/dev/null"}.merge(config)
          config = Config.from_parsed_yaml("logger" => logger_config)
          Factory.build(device: device, config: config, **options)
        end
      end
    end
  end
end
