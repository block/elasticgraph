# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file is contains RSpec configuration and common support code for `elasticgraph-rack`.
# Note that it gets loaded by `spec_support/spec_helper.rb` which contains common spec support
# code for all ElasticGraph test suites.

ENV["RACK_ENV"] = "test"

RSpec.configure do |config|
  config.define_derived_metadata(absolute_file_path: %r{/elasticgraph-rack/}) do |meta|
    meta[:builds_graphql] = true
  end

  config.when_first_matching_example_defined(:rack_app) { require "support/rack_app" }
end