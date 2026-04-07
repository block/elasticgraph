# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file contains RSpec configuration for `elasticgraph-json_ingestion`.
# It is loaded by the shared spec helper at `spec_support/spec_helper.rb`.

RSpec.configure do |config|
  config.when_first_matching_example_defined(:json_ingestion_schema) do
    require "support/json_ingestion_schema_support"
  end
end
