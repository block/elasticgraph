# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/indexer/indexing_failures_error"
require "json"

module ElasticGraph
  module IndexerLambda
    # Responsible for handling lambda event payloads from an SQS lambda trigger.
    #
    # @private
    class SqsProcessor
      def initialize(indexer_processor, report_batch_item_failures:, logger:, s3_client: nil)
        @indexer_processor = indexer_processor
        @report_batch_item_failures = report_batch_item_failures
        @logger = logger
        @s3_client = s3_client
      end

      # Processes the ElasticGraph events in the given `lambda_event`, indexing the data in the datastore.
      def process(lambda_event, refresh_indices: false)
        events = events_from(lambda_event)
        failures = @indexer_processor.process_returning_failures(events, refresh_indices: refresh_indices)

        if failures.any?
          failures_error = Indexer::IndexingFailuresError.for(failures: failures, events: events)
          raise failures_error unless @report_batch_item_failures
          @logger.error(failures_error.message)
        end

        format_response(failures)
      end

      private

      # Given a lambda event payload, returns an array of raw operations in JSON format.
      #
      # The SQS payload is wrapped in the following format already:
      # See https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html#example-standard-queue-message-event for more details
      # {
      #   Records: {
      #     [
      #        { body: <JSON Lines encoded JSON where each line is a JSON object> },
      #        { body: <JSON Lines encoded JSON where each line is a JSON object> },
      #        ...
      #      ]
      #   }
      # }
      #
      # Each entry in "Records" is a SQS entry.  Since lambda handles some batching
      # for you (with some limits), you can get multiple.
      #
      # We also want to do our own batching in order to cram more into a given payload
      # and issue fewer SQS entries and Lambda invocations when possible. As such, we
      # encoded multiple JSON with JSON Lines (http://jsonlines.org/) in record body.
      # Each JSON Lines object under 'body' should be of the form:
      #
      #  {op: 'upsert', __typename: 'Payment', id: "123", version: "1", record: {...} } \n
      #  {op: 'upsert', __typename: 'Payment', id: "123", version: "2", record: {...} } \n
      #   ...
      # Note: "\n" at the end of each line is a single byte newline control character, instead of a string sequence
      def events_from(lambda_event)
        sqs_received_at_by_message_id = {} # : Hash[String, String]
        lambda_event.fetch("Records").flat_map do |record|
          sqs_metadata = extract_sqs_metadata(record)
          if (message_id = sqs_metadata.fetch("message_id", nil))
            sqs_received_at_by_message_id[message_id] = sqs_metadata.dig("latency_timestamps", "sqs_received_at")
          end
          parse_jsonl(record.fetch("body")).map do |event|
            ElasticGraph::Support::HashUtil.deep_merge(event, sqs_metadata)
          end
        end.tap do
          @logger.info({
            "message_type" => "ReceivedSqsMessages",
            "sqs_received_at_by_message_id" => sqs_received_at_by_message_id
          })
        end
      end

      S3_OFFLOADING_INDICATOR = '["software.amazon.payloadoffloading.PayloadS3Pointer"'

      def parse_jsonl(jsonl_string)
        if jsonl_string.start_with?(S3_OFFLOADING_INDICATOR)
          jsonl_string = get_payload_from_s3(jsonl_string)
        end
        jsonl_string.split("\n").map { |event| JSON.parse(event) }
      end

      def extract_sqs_metadata(record)
        sqs_timestamps = {
          "processing_first_attempted_at" => millis_to_iso8601(record.dig("attributes", "ApproximateFirstReceiveTimestamp")),
          "sqs_received_at" => millis_to_iso8601(record.dig("attributes", "SentTimestamp"))
        }.compact

        {
          "latency_timestamps" => (sqs_timestamps unless sqs_timestamps.empty?),
          "message_id" => record["messageId"]
        }.compact
      end

      def millis_to_iso8601(millis)
        return unless millis
        seconds, millis = millis.to_i.divmod(1000)
        Time.at(seconds, millis, :millisecond).getutc.iso8601(3)
      end

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

      # The s3 client is being lazily initialized, as it's slow to import/init and it will only be used
      # in rare scenarios where large messages need offloaded from SQS -> S3.
      # See: (https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-s3-messages.html)
      def s3_client
        @s3_client ||= begin
          require "aws-sdk-s3"
          Aws::S3::Client.new
        end
      end

      # Formats the response, including any failures, based on
      # https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html#services-sqs-batchfailurereporting
      def format_response(failures)
        failure_ids = failures.map do |failure| # $ {"itemIdentifier" => String}
          {"itemIdentifier" => failure.event["message_id"]}
        end

        if failure_ids.any? { |f| f.fetch("itemIdentifier").nil? }
          # If we are not able to identify one or more failed events, then we must raise an exception instead of
          # returning `batchItemFailures`. Otherwise, the unidentified failed events will not get retried.
          raise Errors::MessageIdsMissingError, "Unexpected: some failures did not have a `message_id`, so we are raising an exception instead of returning `batchItemFailures`."
        end

        {"batchItemFailures" => failure_ids}
      end
    end
  end
end
