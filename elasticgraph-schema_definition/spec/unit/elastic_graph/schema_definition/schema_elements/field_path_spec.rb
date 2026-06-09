# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/api"
require "elastic_graph/schema_definition/schema_elements/field_path"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      class FieldPath
        RSpec.describe Resolver do
          it "can only be created after the user definition is complete, to avoid problems" do
            api = build_api

            expect {
              Resolver.new(api.state)
            }.to raise_error Errors::SchemaError, a_string_including(
              "cannot be created before the user definition of the schema is complete"
            )

            api.results # signals the definition is complete

            expect(Resolver.new(api.state)).to be_a Resolver
          end

          it "describes resolved paths using the parent type name and the `name_in_index` of each part" do
            api = build_api

            api.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "cost", "Money"
              t.index "widgets"
            end

            api.object_type "Money" do |t|
              t.field "amount", "Int", name_in_index: "amount_in_index"
            end

            api.results # signals the definition is complete

            widget_type = api.state.object_types_by_name.fetch("Widget")
            path = Resolver.new(api.state).resolve_public_path(widget_type, "cost.amount") { |field| true }

            expect(path.fully_qualified_path_in_index).to eq("Widget.cost.amount_in_index")
          end

          def build_api
            schema_elements = SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: "snake_case")
            API.new(schema_elements, true)
          end
        end
      end
    end
  end
end
