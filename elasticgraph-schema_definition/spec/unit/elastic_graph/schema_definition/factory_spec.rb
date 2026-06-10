# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"
require "elastic_graph/schema_definition/api"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe Factory do
      it "can create an object type without a customization block" do
        object_type = build_api.factory.new_object_type("Widget")

        expect(object_type.name).to eq("Widget")
      end

      it "can create an index without a customization block" do
        api = build_api

        api.object_type "Widget" do |t|
          t.field "id", "ID!"
          t.index "widgets"
        end

        index = api.state.object_types_by_name.fetch("Widget").own_index_def
        expect(index.name).to eq("widgets")
      end

      def build_api
        API.new(
          SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: :snake_case, overrides: {}),
          true,
          extension_modules: []
        )
      end
    end
  end
end
