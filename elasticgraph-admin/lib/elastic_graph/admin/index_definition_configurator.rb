# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin/index_definition_configurator/for_index"
require "elastic_graph/admin/index_definition_configurator/for_index_template"

module ElasticGraph
  class Admin
    module IndexDefinitionConfigurator
      def self.new(datastore_client, index_def, env_agnostic_index_config, output, clock)
        if index_def.rollover_index_template?
          ForIndexTemplate.new(datastore_client, _ = index_def, env_agnostic_index_config, output, clock)
        else
          ForIndex.new(datastore_client, _ = index_def, env_agnostic_index_config, output)
        end
      end
    end
  end
end
