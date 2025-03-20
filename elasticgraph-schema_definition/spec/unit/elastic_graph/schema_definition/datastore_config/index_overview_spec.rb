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
    RSpec.describe "Datastore config -- index overview" do
      include_context "IndexDefinitionSpecSupport"

      it "orders the indices alphabetically for consistent dump output" do
        config1 = all_index_configs_for do |s|
          s.object_type "AType" do |t|
            t.field "id", "ID!"
            t.index "a_type"
          end

          s.object_type "BType" do |t|
            t.field "id", "ID!"
            t.index "b_type"
          end
        end

        config2 = all_index_configs_for do |s|
          s.object_type "BType" do |t|
            t.field "id", "ID!"
            t.index "b_type"
          end

          s.object_type "AType" do |t|
            t.field "id", "ID!"
            t.index "a_type"
          end
        end

        expect(config1.keys).to eq ["a_type", "b_type"]
        expect(config2.keys).to eq ["a_type", "b_type"]
      end

      it "dumps an index with `rollover` as a template with and `index_pattern`" do
        widgets = index_template_configs_for "widgets" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "created_at", "DateTime!"
            t.index "widgets" do |i|
              i.rollover :monthly, "created_at"
            end
          end
        end.first

        components = index_configs_for "components" do |s|
          s.object_type "Component" do |t|
            t.field "id", "ID!"
            t.index "components"
          end
        end.first

        expect(widgets).to match(
          "template" => {
            "settings" => an_instance_of(Hash),
            "mappings" => an_instance_of(Hash),
            "aliases" => {}
          },
          "index_patterns" => ["widgets_rollover__*"]
        )

        expect(components).to match(
          "settings" => an_instance_of(Hash),
          "mappings" => an_instance_of(Hash),
          "aliases" => {}
        )
      end

      it "dumps each index definition under either `indices` or `index_templates` based on if it has rollover config" do
        datastore_config = define_schema(schema_element_name_form: :snake_case) do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "created_at", "DateTime!"
            t.index "widgets" do |i|
              i.rollover :monthly, "created_at"
            end
          end

          s.object_type "Component" do |t|
            t.field "id", "ID!"
            t.index "components"
          end
        end.datastore_config

        expect(datastore_config.fetch("indices").keys).to contain_exactly("components")
        expect(datastore_config.fetch("index_templates").keys).to contain_exactly("widgets")
      end

      it "raises a clear exception if an embedded type is recursively self-referential without using a relation" do
        expect {
          all_index_configs_for do |s|
            s.object_type "Type1" do |t|
              t.field "t2", "Type2"
            end

            s.object_type "Type2" do |t|
              t.field "t3", "Type3"
            end

            s.object_type "Type3" do |t|
              t.field "t1", "Type1"
            end
          end
        }.to raise_error(Errors::SchemaError, a_string_including("self-referential", "Type1", "Type2", "Type3"))
      end

      it "allows an embedded type to have a relation to its parent type (which would otherwise form a cycle)" do
        expect {
          all_index_configs_for do |s|
            s.object_type "Type1" do |t|
              t.field "t2", "Type2"
            end

            s.object_type "Type2" do |t|
              t.field "t3", "Type3"
            end

            s.object_type "Type3" do |t|
              t.relates_to_one "t1", "Type1", via: "t1_id", dir: :out
            end
          end
        }.not_to raise_error
      end

      it "does not allow an index to have the infix follover marker in the name, since ElasticGraph uses that to mark and parse rollover index names" do
        expect {
          index_template_configs_for "widgets" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.index "widget#{ROLLOVER_INDEX_INFIX_MARKER}"
            end
          end
        }.to raise_error Errors::SchemaError, a_string_including("invalid index definition name", ROLLOVER_INDEX_INFIX_MARKER)
      end

      it "ignores interface types" do
        configs = all_index_configs_for do |s|
          s.interface_type "MyType" do |t|
            t.field "id", "ID!"
          end
        end

        expect(configs.keys).to eq []
      end

      def all_index_configs_for(index_document_sizes: false, schema_element_name_form: "snake_case", &schema_definition)
        datastore_config = define_schema(
          index_document_sizes: index_document_sizes,
          schema_element_name_form: schema_element_name_form,
          &schema_definition
        ).datastore_config

        datastore_config.fetch("indices")
      end
    end
  end
end
