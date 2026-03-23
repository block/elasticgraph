# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "aws-sdk-s3"
require "elastic_graph/errors"
require "elastic_graph/indexer_lambda/sqs_message_body_loader"
require "elastic_graph/spec_support/lambda_function"
require "json"

module ElasticGraph
  module IndexerLambda
    RSpec.describe SqsMessageBodyLoader do
      describe "#load_body" do
        it "returns inline SQS message bodies unchanged" do
          loader = described_class.new

          loaded_body = loader.load_body(sqs_record: {"body" => "{\"field1\":{}}"})

          expect(loaded_body).to eq("{\"field1\":{}}")
        end

        it "retrieves large messages from S3 when an ElasticGraph event was offloaded there" do
          bucket_name = "test-bucket-name"
          s3_key = "88680f6d-53d4-4143-b8c7-f5b1189213b6"
          body = "{\"field1\":{}}\n{\"field2\":{}}"
          s3_client = Aws::S3::Client.new(stub_responses: true)
          loader = described_class.new(s3_client: s3_client)

          sqs_record = {
            "body" => JSON.generate([
              "software.amazon.payloadoffloading.PayloadS3Pointer",
              {"s3BucketName" => bucket_name, "s3Key" => s3_key}
            ])
          }

          s3_client.stub_responses(:get_object, ->(context) {
            expect(context.params).to include(bucket: bucket_name, key: s3_key)
            {body: body}
          })

          expect(loader.load_body(sqs_record: sqs_record)).to eq(body)
        end

        it "raises a detailed error when fetching from S3 fails" do
          bucket_name = "test-bucket-name"
          s3_key = "88680f6d-53d4-4143-b8c7-f5b1189213b6"
          s3_client = Aws::S3::Client.new(stub_responses: true)
          loader = described_class.new(s3_client: s3_client)

          sqs_record = {
            "body" => JSON.generate([
              "software.amazon.payloadoffloading.PayloadS3Pointer",
              {"s3BucketName" => bucket_name, "s3Key" => s3_key}
            ])
          }

          s3_client.stub_responses(:get_object, "NoSuchkey")

          expect {
            loader.load_body(sqs_record: sqs_record)
          }.to raise_error Errors::S3OperationFailedError, a_string_including(
            "Error reading large message from S3. bucket: `#{bucket_name}` key: `#{s3_key}` message: `stubbed-response-error-message`"
          )
        end
      end

      context "when instantiated without an S3 client injection" do
        include_context "lambda function"

        it "lazily creates the S3 client when needed" do
          expect(described_class.new.send(:s3_client)).to be_a Aws::S3::Client
        end
      end
    end
  end
end
