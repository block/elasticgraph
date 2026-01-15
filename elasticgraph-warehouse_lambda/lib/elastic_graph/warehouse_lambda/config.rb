# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/config"

module ElasticGraph
  class WarehouseLambda
    class Config < Support::Config.define(:s3_path_prefix)
      json_schema at: "warehouse",
        optional: false,
        description: "Configuration for the warehouse lambda used by `elasticgraph-warehouse_lambda`.",
        properties: {
          s3_path_prefix: {
            description: "The S3 path prefix to use when storing data files.",
            type: "string",
            minLength: 1,
            pattern: /\S/.source, # Requires at least one non-whitespace character
            examples: ["Data001", "my-prefix"]
          }
        },
        required: ["s3_path_prefix"]
    end
  end
end
