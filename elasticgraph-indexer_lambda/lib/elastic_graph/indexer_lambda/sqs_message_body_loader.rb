# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "json"

module ElasticGraph
  module IndexerLambda
    # Resolves the raw body of an SQS message, including fetching offloaded payloads from S3.
    #
    # @private
    class SqsMessageBodyLoader
      S3_OFFLOADING_INDICATOR = '["software.amazon.payloadoffloading.PayloadS3Pointer"'

      def initialize(s3_client: nil)
        @s3_client = s3_client
      end

      # Loads the message body for the given SQS record.
      #
      # @param sqs_record [Hash] full SQS record carrying the body
      # @return [String] resolved SQS message body
      def load_body(sqs_record:)
        body = sqs_record.fetch("body")
        return body unless body.start_with?(S3_OFFLOADING_INDICATOR)

        get_payload_from_s3(body)
      end

      private

      def get_payload_from_s3(json_string)
        s3_pointer = JSON.parse(json_string)[1]
        bucket_name = s3_pointer.fetch("s3BucketName")
        object_key = s3_pointer.fetch("s3Key")

        begin
          s3_client.get_object(bucket: bucket_name, key: object_key).body.read
        rescue Aws::S3::Errors::ServiceError => e
          raise Errors::S3OperationFailedError, "Error reading large message from S3. bucket: `#{bucket_name}` key: `#{object_key}` message: `#{e.message}`"
        end
      end

      # The S3 client is lazily initialized because loading the AWS SDK is relatively expensive,
      # and offloaded SQS messages should be uncommon.
      def s3_client
        @s3_client ||= begin
          require "aws-sdk-s3"
          Aws::S3::Client.new
        end
      end
    end
  end
end
