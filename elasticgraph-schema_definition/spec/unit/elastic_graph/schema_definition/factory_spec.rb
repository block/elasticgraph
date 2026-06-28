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

      it "can create a namespace type without a customization block" do
        namespace_type = build_api.factory.new_namespace_type("WidgetNamespace")

        expect(namespace_type.name).to eq("WidgetNamespace")
        expect(namespace_type).to be_graphql_only
        expect(namespace_type.default_graphql_resolver).to be nil
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

      it "builds namespace types through `new_object_type` so factory extensions that customize object types also apply to namespace types" do
        marker = Module.new
        customizer = Module.new do
          define_method(:new_object_type) do |name, &block|
            super(name) do |type|
              type.extend(marker)
              block&.call(type)
            end
          end
        end

        factory = build_api.factory
        factory.extend(customizer)

        object_type = factory.new_object_type("Widget")
        customized_namespace_type = nil
        namespace_type = factory.new_namespace_type("WidgetNamespace") do |type|
          customized_namespace_type = type
        end

        expect(namespace_type).to be_a(SchemaElements::ObjectType)
        # It also went through the overridden `new_object_type`, like an ordinary object type.
        expect(object_type).to be_a(marker)
        expect(namespace_type).to be_a(marker)
        expect(customized_namespace_type).to be(namespace_type)
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
