# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "json"
require "logger"

module ElasticGraph
  module LambdaSupport
    # A log formatter that supports JSON logging, without requiring _all_ logs to be emitted as JSON.
    #
    # If the `message` is a hash of JSON data, it will produce a JSON-formatted log message combining the
    # standard bits of metadata the AWS Lambda logger already includes in every log message with the passed data.
    #
    # If it is not a hash of JSON data, it will just delegate to the default formatter used by AWS Lambda.
    #
    # This is particularly useful to support cloudwatch metric filtering:
    # https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/FilterAndPatternSyntax.html#metric-filters-extract-json
    class JSONAwareLambdaLogFormatter < ::Logger::Formatter
      # Copied from:
      # https://github.com/aws/aws-lambda-ruby-runtime-interface-client/blob/2.0.0/lib/aws_lambda_ric/lambda_log_formatter.rb#L8
      FORMAT = "%<sev>s, [%<datetime>s #%<process>d] %<severity>5s %<request_id>s -- %<progname>s: %<msg>s"

      def call(severity, time, progname, msg)
        metadata = {
          # These bits of metadata come from the standard AWS Lambda log formatter:
          # https://github.com/aws/aws-lambda-ruby-runtime-interface-client/blob/2.0.0/lib/aws_lambda_ric/lambda_log_formatter.rb#L11-L12
          sev: severity[0..0],
          datetime: format_datetime(time),
          process: $$,
          severity: severity,
          # standard:disable Style/GlobalVars -- don't have a choice here; this is what the AWS Lambda runtime sets.
          request_id: $_global_aws_request_id,
          # standard:enable Style/GlobalVars
          progname: progname
        }

        if msg.is_a?(::Hash)
          ::JSON.generate(msg.merge(metadata), space: " ")
        else
          # See https://github.com/aws/aws-lambda-ruby-runtime-interface-client/blob/2.0.0/lib/aws_lambda_ric/lambda_log_formatter.rb
          (FORMAT % metadata.merge({msg: msg2str(msg)})).encode!("UTF-8")
        end
      end
    end
  end
end
