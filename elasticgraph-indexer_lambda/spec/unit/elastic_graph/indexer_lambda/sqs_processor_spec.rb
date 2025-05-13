# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/indexer/failed_event_error"
require "elastic_graph/indexer/processor"
require "elastic_graph/indexer_lambda/sqs_processor"
require "elastic_graph/spec_support/lambda_function"
require "json"
require "aws-sdk-s3"

module ElasticGraph
  module IndexerLambda
    RSpec.describe SqsProcessor, :capture_logs do
      let(:indexer_processor) { instance_double(Indexer::Processor, process_returning_failures: []) }

      describe "#process" do
        let(:s3_client) { Aws::S3::Client.new(stub_responses: true) }
        let(:sqs_processor) { build_sqs_processor }

        it "processes a lambda event containing a single SQS message with a single ElasticGraph event" do
          lambda_event = {
            "Records" => [
              {"messageId" => "a", "body" => jsonl({"field1" => {}})}
            ]
          }

          sqs_processor.process(lambda_event)

          expect(indexer_processor).to have_received(:process_returning_failures).with([
            {"field1" => {}, "message_id" => "a"}
          ], refresh_indices: false)
        end

        it "processes a lambda event containing multiple SQS messages" do
          lambda_event = {
            "Records" => [
              {"messageId" => "a", "body" => jsonl({"field1" => {}})},
              {"messageId" => "b", "body" => jsonl({"field2" => {}})},
              {"messageId" => "c", "body" => jsonl({"field3" => {}})}
            ]
          }

          sqs_processor.process(lambda_event)

          expect(indexer_processor).to have_received(:process_returning_failures).with([
            {"field1" => {}, "message_id" => "a"},
            {"field2" => {}, "message_id" => "b"},
            {"field3" => {}, "message_id" => "c"}
          ], refresh_indices: false)
        end

        it "processes a lambda event containing multiple ElasticGraph events in the SQS messages" do
          lambda_event = {
            "Records" => [
              {"messageId" => "a", "body" => jsonl({"field1" => {}}, {"field2" => {}})},
              {"messageId" => "b", "body" => jsonl({"field3" => {}}, {"field4" => {}}, {"field5" => {}})}
            ]
          }

          sqs_processor.process(lambda_event)

          expect(indexer_processor).to have_received(:process_returning_failures).with([
            {"field1" => {}, "message_id" => "a"},
            {"field2" => {}, "message_id" => "a"},
            {"field3" => {}, "message_id" => "b"},
            {"field4" => {}, "message_id" => "b"},
            {"field5" => {}, "message_id" => "b"}
          ], refresh_indices: false)
        end

        it "logs the SQS message ids received in the lambda event and the `sqs_received_at` if available" do
          sent_timestamp_millis = "796010423456"
          sent_timestamp_iso8601 = "1995-03-24T02:00:23.456Z"

          lambda_event = {
            "Records" => [
              {
                "messageId" => "a",
                "body" => jsonl(
                  {"field1" => {}},
                  {"field2" => {}}
                ),
                "attributes" => {
                  "SentTimestamp" => sent_timestamp_millis
                }
              },
              {
                "messageId" => "b",
                "body" => jsonl(
                  {"field3" => {}},
                  {"field4" => {}},
                  {"field5" => {}}
                )
              }
            ]
          }

          expect {
            sqs_processor.process(lambda_event)
          }.to log a_string_including(
            "message_type", "ReceivedSqsMessages", "sqs_received_at_by_message_id", "a", sent_timestamp_iso8601, "b", "null"
          )
        end

        it "raises a clear error if the lambda event does not contain SQS messages under `Records` as expected" do
          lambda_event = {
            "Rows" => [
              {"messageId" => "a", "body" => jsonl({"field1" => {}})},
              {"messageId" => "b", "body" => jsonl({"field2" => {}})},
              {"messageId" => "c", "body" => jsonl({"field1" => {}})}
            ]
          }

          expect {
            sqs_processor.process(lambda_event)
          }.to raise_error(KeyError, a_string_including("Records"))

          expect(indexer_processor).not_to have_received(:process_returning_failures)
        end

        it "raises a clear error if the SQS messages lack a `body` as expected" do
          lambda_event = {
            "Records" => [
              {"messageId" => "a", "data" => jsonl({"field1" => {}})},
              {"messageId" => "b", "data" => jsonl({"field2" => {}})},
              {"messageId" => "c", "data" => jsonl({"field1" => {}})}
            ]
          }

          expect {
            sqs_processor.process(lambda_event)
          }.to raise_error(KeyError, a_string_including("body"))

          expect(indexer_processor).not_to have_received(:process_returning_failures)
        end

        it "retrieves large messages from s3 when an ElasticGraph event was offloaded there" do
          bucket_name = "test-bucket-name"
          s3_key = "88680f6d-53d4-4143-b8c7-f5b1189213b6"
          event_payload = {"test" => "data"}

          lambda_event = {
            "Records" => [
              {"messageId" => "a", "body" => JSON.generate([
                "software.amazon.payloadoffloading.PayloadS3Pointer",
                {"s3BucketName" => bucket_name, "s3Key" => s3_key}
              ])}
            ]
          }

          s3_client.stub_responses(:get_object, ->(context) {
            expect(context.params).to include(bucket: bucket_name, key: s3_key)
            {body: jsonl(event_payload)}
          })

          sqs_processor.process(lambda_event)

          expect(indexer_processor).to have_received(:process_returning_failures).with(
            [event_payload.merge("message_id" => "a")],
            refresh_indices: false
          )
        end

        it "throws a detailed error when fetching from s3 fails" do
          bucket_name = "test-bucket-name"
          s3_key = "88680f6d-53d4-4143-b8c7-f5b1189213b6"

          lambda_event = {
            "Records" => [
              {"messageId" => "a", "body" => JSON.generate([
                "software.amazon.payloadoffloading.PayloadS3Pointer",
                {"s3BucketName" => bucket_name, "s3Key" => s3_key}
              ])}
            ]
          }

          s3_client.stub_responses(:get_object, "NoSuchkey")

          expect {
            sqs_processor.process(lambda_event)
          }.to raise_error Errors::S3OperationFailedError, a_string_including(
            "Error reading large message from S3. bucket: `#{bucket_name}` key: `#{s3_key}` message: `stubbed-response-error-message`"
          )
        end

        it "parses and merges SQS timestamps into non-existing `latency_timestamps` field" do
          approximate_first_receive_timestamp_millis = "1696334412345"
          sent_timestamp_millis = "796010423456"

          approximate_first_receive_timestamp_iso8601 = "2023-10-03T12:00:12.345Z"
          sent_timestamp_iso8601 = "1995-03-24T02:00:23.456Z"

          lambda_event = {
            "Records" => [
              {
                "messageId" => "a",
                "body" => jsonl({"field1" => {}}),
                "attributes" => {
                  "ApproximateFirstReceiveTimestamp" => approximate_first_receive_timestamp_millis,
                  "SentTimestamp" => sent_timestamp_millis
                }
              }
            ]
          }

          sqs_processor.process(lambda_event)

          expect(indexer_processor).to have_received(:process_returning_failures) do |events|
            expect(events.first["latency_timestamps"].size).to eq(2)
            expect(
              events.first["latency_timestamps"]["processing_first_attempted_at"]
            ).to eq(approximate_first_receive_timestamp_iso8601)
            expect(
              events.first["latency_timestamps"]["sqs_received_at"]
            ).to eq(sent_timestamp_iso8601)
          end
        end

        it "parses and merges SQS timestamps into existing `latency_timestamps` field" do
          approximate_first_receive_timestamp_millis = "1696334412345"
          sent_timestamp_millis = "796010423456"

          approximate_first_receive_timestamp_iso8601 = "2023-10-03T12:00:12.345Z"
          sent_timestamp_iso8601 = "1995-03-24T02:00:23.456Z"

          lambda_event = {
            "Records" => [
              {
                "messageId" => "a",
                "body" => jsonl({"latency_timestamps" => {"field1" => "value1"}}),
                "attributes" => {
                  "ApproximateFirstReceiveTimestamp" => approximate_first_receive_timestamp_millis,
                  "SentTimestamp" => sent_timestamp_millis
                }
              }
            ]
          }

          sqs_processor.process(lambda_event)

          expect(indexer_processor).to have_received(:process_returning_failures) do |events|
            expect(events.first["latency_timestamps"].size).to eq(3)
            expect(
              events.first["latency_timestamps"]["processing_first_attempted_at"]
            ).to eq(approximate_first_receive_timestamp_iso8601)
            expect(
              events.first["latency_timestamps"]["sqs_received_at"]
            ).to eq(sent_timestamp_iso8601)
            expect(
              events.first["latency_timestamps"]["field1"]
            ).to eq("value1")
          end
        end

        context "when one or more events fail to process" do
          let(:sqs_processor) { build_sqs_processor }

          it "indicates which SQS messages had failures in the lambda response so that only those messages are retried (while still logging the errors)" do
            allow(indexer_processor).to receive(:process_returning_failures).and_return([
              failure_of("id1", message: "boom1", event: {"id" => "id1", "message_id" => "12"}),
              failure_of("id7", message: "boom7", event: {"id" => "id7", "message_id" => "67"})
            ])

            lambda_event = {
              "Records" => [
                {"messageId" => "12", "body" => jsonl({"id" => "id1"}, {"id" => "id2"})},
                {"messageId" => "34", "body" => jsonl({"id" => "id3"}, {"id" => "id4"})},
                {"messageId" => "5", "body" => jsonl({"id" => "id5"})},
                {"messageId" => "67", "body" => jsonl({"id" => "id6"}, {"id" => "id7"})}
              ]
            }

            response = nil

            expect {
              response = sqs_processor.process(lambda_event)
            }.to log a_string_including(
              "Got 2 failure(s) from 7 event(s):", "boom1", "boom7",
              "These failures came from 2 message(s): 12, 67."
            )

            expect(response).to eq({"batchItemFailures" => [
              {"itemIdentifier" => "12"},
              {"itemIdentifier" => "67"}
            ]})
          end

          it "falls back to raising an `IndexingFailuresError` if the SQS id of an event cannot be determined" do
            allow(indexer_processor).to receive(:process_returning_failures).and_return([
              failure_of("id1", message: "boom1", event: {"id" => "id1"}),
              failure_of("id7", message: "boom7", event: {"id" => "id7", "message_id" => "67"})
            ])

            lambda_event = {
              "Records" => [
                {"body" => jsonl({"id" => "id1"}, {"id" => "id2"})},
                {"messageId" => "34", "body" => jsonl({"id" => "id3"}, {"id" => "id4"})},
                {"messageId" => "5", "body" => jsonl({"id" => "id5"})},
                {"messageId" => "67", "body" => jsonl({"id" => "id6"}, {"id" => "id7"})}
              ]
            }

            expect {
              sqs_processor.process(lambda_event)
            }.to log(a_string_including(
              "Got 2 failure(s) from 7 event(s)", "boom1", "boom7",
              "These failures came from 1 message(s): 67."
            )).and raise_error(
              Errors::MessageIdsMissingError,
              a_string_including("Unexpected: some failures did not have a `message_id`")
            )
          end
        end

        def failure_of(id, message: "boom", event: {})
          instance_double(Indexer::FailedEventError, id: id, message: message, event: event)
        end

        def build_sqs_processor
          super(s3_client: s3_client)
        end
      end

      context "when instantiated without an S3 client injection" do
        include_context "lambda function"

        it "lazily creates the S3 client when needed" do
          expect(build_sqs_processor.send(:s3_client)).to be_a Aws::S3::Client
        end
      end

      def jsonl(*items)
        items.map { |i| ::JSON.generate(i) }.join("\n")
      end

      def build_sqs_processor(**options)
        SqsProcessor.new(indexer_processor, logger: logger, **options)
      end
    end
  end
end
