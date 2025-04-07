# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file is contains RSpec configuration and common support code for `elasticgraph-datastore_core`.
# Note that it gets loaded by `spec_support/spec_helper.rb` which contains common spec support
# code for all ElasticGraph test suites.

require "elastic_graph/spec_support/builds_datastore_core"

module ElasticGraph
  RSpec.configure do |config|
    config.include BuildsDatastoreCore, absolute_file_path: %r{/elasticgraph-datastore_core/}
  end
end

RSpec::Matchers.define_negated_matcher :differ_from, :eq
