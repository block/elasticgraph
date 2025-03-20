# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "../index_definition_spec_support"

module ElasticGraph
  module SchemaDefinition
    ::RSpec.shared_context "IndexMappingsSpecSupport" do
      include_context "IndexDefinitionSpecSupport"

      def index_mapping_for(index_name, **config_overrides, &schema_definition)
        index_mappings_for(index_name, **config_overrides, &schema_definition).first
      end

      def index_mappings_for(...)
        index_configs_for(...).map do |config|
          config.fetch("mappings")
        end
      end
    end
  end
end
