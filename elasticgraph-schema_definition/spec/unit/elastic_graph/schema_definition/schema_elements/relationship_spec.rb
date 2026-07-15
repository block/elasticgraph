# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"
require "elastic_graph/schema_definition/api"
require "elastic_graph/spec_support/schema_definition_helpers"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      RSpec.describe Relationship do
        describe "#parent_relationship" do
          it "stores the parent type ref in its final form, applying any `type_name_overrides` rename" do
            expect(stored_parent_type_ref(type_name_overrides: {"Team" => "RenamedTeam"}).name).to eq "RenamedTeam"
          end

          it "leaves the parent type name unchanged when no `type_name_overrides` applies to it" do
            expect(stored_parent_type_ref(type_name_overrides: {}).name).to eq "Team"
          end
        end

        def stored_parent_type_ref(type_name_overrides:)
          schema_elements = SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: "snake_case")
          api = API.new(schema_elements, true, type_name_overrides: type_name_overrides)

          api.object_type "Player" do |t|
            t.field "id", "ID!"
            t.relates_to_one "statLine", "StatLine", via: "playerId", dir: :in, indexing_only: true do |r|
              r.parent_relationship "Team", "statLines"
            end
          end

          api.state.object_types_by_name.fetch("Player").relationships_by_name.fetch("statLine").parent_ref.type_ref
        end
      end
    end
  end
end
