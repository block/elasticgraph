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
    # Intended to be mixed into {FromDisk} and other implementations of the same interface
    # (such as {SchemaDefinition::Results}.
    module ArtifactsHelperMethods
      # Provides accesses to the datastore scripts, typically written using the [painless scripting
      # language](https://www.elastic.co/docs/explore-analyze/scripting/modules-scripting-painless).
      #
      # @return [Hash<String, Hash<String, Object>>]
      def datastore_scripts
        datastore_config.fetch("scripts")
      end

      # Provides accesses to the datastore index templates, which are used for a rollover index defined using
      # {SchemaDefinition::Indexing::Index#rollover}.
      #
      # @return [Hash<String, Hash<String, Object>>]
      def index_templates
        datastore_config.fetch("index_templates")
      end

      # Provides accesses to the datastore indices, used for an index that does not rollover.
      #
      # @return [Hash<String, Hash<String, Object>>]
      def indices
        datastore_config.fetch("indices")
      end

      # Provides access to the [mappings](https://www.elastic.co/docs/manage-data/data-store/mapping) of both the
      # {#index_templates} and {#indices}.
      #
      # @return [Hash<String, Hash<String, Object>>]
      def index_mappings_by_index_def_name
        @index_mappings_by_index_def_name ||= index_templates
          .transform_values { |config| config.fetch("template").fetch("mappings") }
          .merge(indices.transform_values { |config| config.fetch("mappings") })
      end
    end
  end
end
