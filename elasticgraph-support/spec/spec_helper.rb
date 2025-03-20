# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file is contains RSpec configuration and common support code for `elasticgraph-support`.
# Note that it gets loaded by `spec_support/spec_helper.rb` which contains common spec support
# code for all ElasticGraph test suites.

# Here we load the version file so that it gets covered. When running the test suite without using bundler (e.g. after setting
# things up with `bundler --standalone`) the version file will not be pre-loaded from the gemspec like it usually is when run
# through bundler so we need to load it for it to be covered.
require "elastic_graph/version"

module ElasticGraph
  module Support
    SPEC_ROOT = __dir__
  end
end
