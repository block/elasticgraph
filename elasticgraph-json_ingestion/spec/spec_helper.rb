# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file contains RSpec configuration for `elasticgraph-json_ingestion`.
# It is loaded by the shared spec helper at `spec_support/spec_helper.rb`.

require "elastic_graph/json_ingestion/schema_definition/api_extension"
require "elastic_graph/spec_support/schema_definition_helpers"

RSpec.configure do |config|
  config.define_derived_metadata(absolute_file_path: %r{/elasticgraph-json_ingestion/}) do |meta|
    meta[:json_ingestion_schema_definition] = true
  end

  config.include_context "SchemaDefinitionHelpers", :json_ingestion_schema_definition
end
