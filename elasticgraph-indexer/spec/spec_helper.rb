# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file is contains RSpec configuration and common support code for `elasticgraph-indexer`.
# Note that it gets loaded by `spec_support/spec_helper.rb` which contains common spec support
# code for all ElasticGraph test suites.

RSpec.configure do |config|
  config.define_derived_metadata(absolute_file_path: %r{/elasticgraph-indexer/}) do |meta|
    meta[:builds_indexer] = true
  end
end
