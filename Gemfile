# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

source "https://rubygems.org"

require_relative "elasticgraph-support/lib/elastic_graph/version"

# Depend on each ElasticGraph gem in the repo.
::Dir.glob("#{__dir__}/*/*.gemspec").map do |gemspec|
  elasticgraph_gem = ::File.basename(::File.dirname(gemspec))
  gem elasticgraph_gem, ::ElasticGraph::VERSION, path: elasticgraph_gem
end

# Defer to `Gemfile-shared` for dependencies on non-ElasticGraph gems.
eval_gemfile "Gemfile-shared"

# `tmp` and `log` are git-ignored but many of our build tasks and scripts expect them to exist.
# We create them here since `Gemfile` evaluation happens before anything else.
require "fileutils"
::FileUtils.mkdir_p("#{__dir__}/log")
::FileUtils.mkdir_p("#{__dir__}/tmp")
