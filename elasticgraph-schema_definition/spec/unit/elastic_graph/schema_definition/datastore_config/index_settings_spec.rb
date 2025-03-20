# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "index_definition_spec_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "Datastore config -- index settings" do
      include_context "IndexDefinitionSpecSupport"

      it "returns reasonable default settings that we want to use for an index" do
        settings = index_settings_for "my_type" do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID"
            t.index "my_type"
          end
        end

        expect(settings).to include(
          "index.mapping.ignore_malformed" => false,
          "index.mapping.coerce" => false,
          "index.number_of_replicas" => 1,
          "index.number_of_shards" => 1
        )
      end

      it "allows specific settings to be overridden via the `index` options in the schema definitionAPI" do
        settings = index_settings_for "my_type" do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID"
            t.index "my_type", number_of_replicas: 2, mapping: {coerce: true}, some: {other_setting: false}
          end
        end

        expect(settings).to include(
          "index.mapping.ignore_malformed" => false,
          "index.mapping.coerce" => true,
          "index.number_of_replicas" => 2,
          "index.number_of_shards" => 1,
          "index.some.other_setting" => false
        )
      end

      it "does not include `route_with` or `rollover` options in the dumped settings, regardless of the schema form, since they are not used by the datastore itself" do
        camel_settings, snake_settings = %w[snake_case camelCase].map do |form|
          index_template_settings_for "my_type", schema_element_name_form: form do |s|
            s.object_type "MyType" do |t|
              t.field "id", "ID!"
              t.field "created_at", "DateTime!"
              t.field "name", "String!"
              t.index "my_type" do |i|
                i.route_with "name"
                i.rollover :monthly, "created_at"
              end
            end
          end
        end

        expect(camel_settings).to eq(Indexing::Index::DEFAULT_SETTINGS)
        expect(snake_settings).to eq(Indexing::Index::DEFAULT_SETTINGS)
      end

      def index_settings_for(index_name, **config_overrides, &schema_definition)
        index_configs_for(index_name, **config_overrides, &schema_definition)
          .first
          .fetch("settings")
      end

      def index_template_settings_for(index_name, **config_overrides, &schema_definition)
        index_template_configs_for(index_name, **config_overrides, &schema_definition)
          .first
          .fetch("template")
          .fetch("settings")
      end
    end
  end
end
