# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "yaml"

module CustomArtifactsExample
  Provider = ::Data.define(:type_names, :label)

  module Artifacts
    def self.from_disk(artifacts_dir, config:)
      Provider.new(::YAML.safe_load_file(::File.join(artifacts_dir, "custom_types.yaml")), config.fetch(:label))
    end

    def self.from_schema_definition(results, config:)
      Provider.new(results.state.object_types_by_name.keys.sort, config.fetch(:label))
    end
  end
end
