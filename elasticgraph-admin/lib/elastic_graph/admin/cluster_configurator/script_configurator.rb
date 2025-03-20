# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin/cluster_configurator/action_reporter"
require "elastic_graph/errors"

module ElasticGraph
  class Admin
    class ClusterConfigurator
      class ScriptConfigurator
        def initialize(datastore_client:, script_context:, script_id:, script:, output:)
          @datastore_client = datastore_client
          @script_context = script_context
          @script_id = script_id
          @script = script
          @action_reporter = ActionReporter.new(output)
        end

        def validate
          case existing_datastore_script
          when :not_found, @script
            []
          else
            [
              "#{@script_context} script #{@script_id} already exists in the datastore but has different contents. " \
                "\n\nScript in the datastore:\n#{::YAML.dump(existing_datastore_script)}" \
                "\n\nDesired script:\n#{::YAML.dump(@script)}"
            ]
          end
        end

        def configure!
          if existing_datastore_script == :not_found
            @datastore_client.put_script(id: @script_id, body: {script: @script}, context: @script_context)
            @action_reporter.report_action "Stored #{@script_context} script: #{@script_id}"
          end
        end

        private

        def existing_datastore_script
          @existing_datastore_script ||= @datastore_client
            .get_script(id: @script_id)
            &.fetch("script") || :not_found
        end
      end
    end
  end
end
