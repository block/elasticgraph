# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/schema_definition/results"
require "support/validate_script_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "Static scripts", :uses_datastore do
      include ValidateScriptSupport

      Results::STATIC_SCRIPT_REPO.scripts.each do |script|
        describe "the `#{script.scoped_name}` script" do
          it "compiles in the datastore successfully" do
            validate_script(script.id, script.to_artifact_payload)
          end
        end
      end
    end
  end
end
