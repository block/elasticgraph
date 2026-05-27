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
        api = API.new(
          SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: :snake_case, overrides: {}),
          true,
          extension_modules: []
        )

        object_type = api.factory.new_object_type("Widget")

        expect(object_type.name).to eq("Widget")
      end
    end
  end
end
