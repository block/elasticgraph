# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# This file contains RSpec configuration for `elasticgraph-proto_ingestion`.
# It is loaded by the shared spec helper at `spec_support/spec_helper.rb`.

RSpec.configure do |config|
  config.define_derived_metadata(absolute_file_path: %r{/elasticgraph-proto_ingestion/}) do |meta|
    meta[:proto_schema] = true
  end

  config.when_first_matching_example_defined(:proto_schema) do
    require "support/proto_schema_support"
  end

  # Examples tagged with `:requires_buf` run the real Buf CLI, and are skipped where it is not installed.
  config.before(:example, :requires_buf) do
    require "open3"
    _, _, status = ::Open3.capture3("buf", "--version")
    # simplecov:disable -- CI installs Buf, so the skips are only reached on machines without it.
    skip "Buf CLI is not installed" unless status.success?
  rescue ::Errno::ENOENT
    skip "Buf CLI is not installed"
    # simplecov:enable
  end
end
