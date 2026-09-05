# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

class ExampleIndexingEventDecoder
  attr_reader :config, :schema_artifacts, :logger

  def initialize(config:, schema_artifacts:, logger:)
    @config = config
    @schema_artifacts = schema_artifacts
    @logger = logger
  end

  def decode(payload)
    payload.split(config.fetch("delimiter")).map { |value| {"value" => value} }
  end
end

class InvalidIndexingEventDecoder
  def initialize(config:, schema_artifacts:, logger:)
  end
end
