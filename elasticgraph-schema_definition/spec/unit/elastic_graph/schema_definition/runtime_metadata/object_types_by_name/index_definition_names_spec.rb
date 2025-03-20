# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "object_type_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #object_types_by_name #index_definition_names" do
      include_context "object type metadata support"

      context "on a normal indexed type" do
        it "dumps them based on the defined indices" do
          metadata = object_type_metadata_for "Widget" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.index "widgets"
            end
          end

          expect(metadata.index_definition_names).to eq ["widgets"]
        end

        it "does not allow it to change its indexable status after the `object_type` call" do
          expect {
            object_type_metadata_for "WidgetAggregation" do |s|
              the_type = nil

              s.object_type "Widget" do |t|
                the_type = t
                t.field "id", "ID"
                t.field "description", "String", name_in_index: "description_index"
                t.index "widgets"
              end

              the_type.indices.clear
            end
          }.to raise_error(a_string_including("can't modify frozen Array"))
        end
      end

      context "on an embedded object type" do
        it "does not dump any" do
          metadata = object_type_metadata_for "WidgetOptions" do |s|
            s.object_type "WidgetOptions" do |t|
              t.field "size", "Int", name_in_index: "size_index"
            end
          end

          expect(metadata.index_definition_names).to be_empty
        end

        it "does not allow it to change its indexable status after the `object_type` call" do
          expect {
            object_type_metadata_for "WidgetAggregation" do |s|
              the_type = nil

              s.object_type "Widget" do |t|
                the_type = t
                t.field "id", "ID"
                t.field "description", "String", name_in_index: "description_index"
              end

              the_type.index "widgets"
            end
          }.to raise_error(a_string_including("can't modify frozen Array"))
        end
      end

      on_a_type_union_or_interface_type do |type_def_method|
        it "dumps them based on indices defined directly on the supertype" do
          metadata = object_type_metadata_for "Thing" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              link_subtype_to_supertype(t, "Thing")
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              link_subtype_to_supertype(t, "Thing")
            end

            s.public_send type_def_method, "Thing" do |t|
              link_supertype_to_subtypes(t, "Widget", "Component")
              t.index "things"
            end
          end

          expect(metadata.index_definition_names).to eq ["things"]
        end

        it "does not dump any when no direct index is defined on it (even if the subtypes have indices)" do
          metadata = object_type_metadata_for "Thing" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              # Use an alternate `name_in_index` to force `metadata` not to be `nil`.
              t.field "workspace_id", "ID!", name_in_index: "wid"
              link_subtype_to_supertype(t, "Thing")
              t.index "widgets"
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              link_subtype_to_supertype(t, "Thing")
              t.index "components"
            end

            s.public_send type_def_method, "Thing" do |t|
              link_supertype_to_subtypes(t, "Widget", "Component")
            end
          end

          expect(metadata.index_definition_names).to eq([])
        end

        it "does not allow it to change its indexable status after the `#{type_def_method}` call" do
          expect {
            object_type_metadata_for "Thing" do |s|
              the_type = nil

              s.object_type "Widget" do |t|
                t.field "id", "ID!"
                link_subtype_to_supertype(t, "Thing")
              end

              s.object_type "Component" do |t|
                t.field "id", "ID!"
                link_subtype_to_supertype(t, "Thing")
              end

              s.public_send type_def_method, "Thing" do |t|
                the_type = t
                link_supertype_to_subtypes(t, "Widget", "Component")
              end

              the_type.index "widgets"
            end
          }.to raise_error(a_string_including("can't modify frozen Array"))
        end
      end
    end
  end
end
