# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # @private
      class ConfiguredGraphQLResolver < ::Data.define(:name, :config)
        NAME = "name"
        CONFIG = "config"

        def self.from_hash(hash)
          new(
            name: hash.fetch(NAME).to_sym,
            config: Support::HashUtil.symbolize_keys(hash[CONFIG] || {})
          )
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            CONFIG => Support::HashUtil.stringify_keys(config),
            NAME => name.to_s
          }.reject { |_, v| v.empty? }
        end
      end
    end
  end
end
