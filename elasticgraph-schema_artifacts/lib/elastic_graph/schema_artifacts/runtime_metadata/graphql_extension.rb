# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      class GraphQLExtension < ::Data.define(:extension_ref)
        def self.loader
          @loader ||= ExtensionLoader.new(Module.new)
        end

        EXTENSION_REF = "extension_ref"

        def load_extension
          Extension.load_from_hash(extension_ref, via: GraphQLExtension.loader)
        end

        def self.from_hash(hash)
          new(
            extension_ref: hash.fetch(EXTENSION_REF)
          )
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            EXTENSION_REF => extension_ref
          }
        end
      end
    end
  end
end
