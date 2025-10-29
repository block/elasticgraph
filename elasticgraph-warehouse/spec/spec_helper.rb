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
  config.when_first_matching_example_defined(:warehouse_schema) do
    require "support/warehouse_schema_support"
  end
end
