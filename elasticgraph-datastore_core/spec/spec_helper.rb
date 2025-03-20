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
  module DatastoreCoreSpecHelpers
    include BuildsDatastoreCore

    def build_datastore_core(**options, &block)
      # Default `for_context` to :admin since it is a more limited context.
      options = {for_context: :admin}.merge(options)
      super(**options, &block)
    end
  end

  RSpec.configure do |config|
    config.include DatastoreCoreSpecHelpers, absolute_file_path: %r{/elasticgraph-datastore_core/}
  end
end

RSpec::Matchers.define_negated_matcher :differ_from, :eq
