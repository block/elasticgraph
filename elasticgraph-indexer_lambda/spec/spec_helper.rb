# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file is contains RSpec configuration and common support code for `elasticgraph-indexer_lambda`.
# Note that it gets loaded by `spec_support/spec_helper.rb` which contains common spec support
# code for all ElasticGraph test suites.

RSpec.configure do |config|
  # The aws-sdk-s3 gem requires that an XML library be available on the load path. Before we upgraded to
  # Ruby 3, that requirement was satisfied by rexml from the standard library. In Ruby 3, it's been moved
  # out of the standard library (into a bundled gem), which means that it isn't automatically available.
  # However, `rexml` is a transitive dependency of some of the other gems of our bundle (rubocop, webmock)
  # and it therefore winds up on our load path. Its presence on the load path allowed our tests to pass
  # but failures to occur in production (where rexml was no longer available after we upgraded to Ruby 3.x).
  #
  # To reproduce that production issue, we want to remove rexml from the load path here. However, we can only
  # do so if this spec run is limited to spec files from this gem's spec suite. If any spec files are being
  # run from other gems (e.g. for the entire ElasticGraph test suite) we must leave it on the load path so
  # that it's available for the other things that need it.
  #
  # Our CI build runs each gem's test suite individually and also runs the entire test suite all together so
  # this should still guard against a regression even though the "standard" way we run our tests (e.g. the
  # entire test suite) won't benefit from this.
  #
  # :nocov: -- on any given test run only one side of this conditional is covered.
  if config.files_to_run.all? { |f| f.start_with?(__dir__) }
    $LOAD_PATH.delete_if { |path| path.include?("rexml") }
  end
  # :nocov:
end
