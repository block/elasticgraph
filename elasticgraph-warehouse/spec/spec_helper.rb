# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file contains RSpec configuration for `elasticgraph-warehouse`.
# It is loaded by the shared spec helper at `spec_support/spec_helper.rb`.

RSpec.configure do |config|
  config.define_derived_metadata(absolute_file_path: %r{/elasticgraph-warehouse/}) do |meta|
    meta[:builds_graphql] = true # we need GraphQL/schema_definition loaded for these specs
  end
end

# Ensure schema definition test helpers are available
require "elastic_graph/schema_definition/test_support"

# Ensure the extension is loaded so monkey patches are active
require "elastic_graph/warehouse"
