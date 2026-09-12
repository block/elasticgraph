# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Runtime metadata related to a field on a datastore index definition.
      #
      # @private
      class IndexField < ::Data.define(:source, :doc_values_eligible)
        DOC_VALUES_ELIGIBLE = "doc_values_eligible"
        SOURCE = "source"

        def initialize(source:, doc_values_eligible: false)
          super
        end

        def self.from_hash(hash)
          new(
            source: hash[SOURCE] || SELF_RELATIONSHIP_NAME,
            doc_values_eligible: hash.fetch(DOC_VALUES_ELIGIBLE, false)
          )
        end

        def to_dumpable_hash
          {
            # Keys here are ordered alphabetically; please keep them that way.
            DOC_VALUES_ELIGIBLE => doc_values_eligible ? true : nil,
            SOURCE => source
          }.compact
        end
      end
    end
  end
end
