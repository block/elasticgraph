# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaArtifacts
    # Mixin that offers convenient helper methods on top of the basic schema artifacts.
    # Intended to be mixed into every implementation of the `_SchemaArtifacts` interface.
    module ArtifactsHelperMethods
      def datastore_scripts
        datastore_config.fetch("scripts")
      end

      def index_templates
        datastore_config.fetch("index_templates")
      end

      def indices
        datastore_config.fetch("indices")
      end

      # Builds a map of index mappings, keyed by index definition name.
      def index_mappings_by_index_def_name
        @index_mappings_by_index_def_name ||= index_templates
          .transform_values { |config| config.fetch("template").fetch("mappings") }
          .merge(indices.transform_values { |config| config.fetch("mappings") })
      end
    end
  end
end
