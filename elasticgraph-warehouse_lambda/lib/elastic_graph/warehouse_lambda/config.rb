# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/config"

module ElasticGraph
  # AWS Lambda integration for exporting ElasticGraph indexing data to S3 as gzipped JSONL files.
  # This allows downstream analytics pipelines, data warehouses, and lakehouses to consume
  # ElasticGraph data without querying the primary datastore.
  class WarehouseLambda
    # Configuration for the warehouse lambda.
    #
    # Defines S3 settings for exporting ElasticGraph data as gzipped JSONL files.
    class Config < Support::Config.define(:s3_path_prefix, :s3_bucket_name, :aws_region)
      json_schema at: "warehouse",
        optional: true,
        description: "Configuration for the warehouse lambda used by `elasticgraph-warehouse_lambda`.",
        properties: {
          s3_path_prefix: {
            description: "The S3 path prefix to use when storing data files.",
            type: "string",
            pattern: /^\S+$/.source, # No whitespace allowed
            examples: ["Data001", "my-prefix"]
          },
          s3_bucket_name: {
            description: "The S3 bucket name to write JSONL files into.",
            type: "string",
            pattern: /^\S+$/.source, # No whitespace allowed
            examples: ["my-warehouse-bucket", "data-lake-prod"]
          },
          aws_region: {
            description: "Optional AWS region for the S3 bucket. If not specified, uses AWS SDK default region resolution (AWS_REGION env var, instance metadata, etc.).",
            type: ["string", "null"],
            pattern: /^\S+$/.source, # No whitespace allowed
            examples: ["us-west-2", "eu-central-1"],
            default: nil
          }
        },
        required: ["s3_path_prefix", "s3_bucket_name"]
    end
  end
end
