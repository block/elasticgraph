# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "object_type_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #object_types_by_name index inheritance" do
      include_context "object type metadata support"

      on_a_type_union_or_interface_type do |type_def_method|
        context "with a comprehensive index inheritance example (Store types)" do
          attr_reader :physical_store_metadata, :mobile_store_metadata, :online_store_metadata, :store_metadata

          before(:context) do
            # Build the schema once and reuse it for all tests in this context.
            # This tests both union and interface inheritance depending on type_def_method.
            #
            # Schema structure:
            # - Store: abstract type (union or interface) with `index "stores"`
            # - PhysicalStore: concrete type with its own `index "physical_stores"` (does not inherit)
            # - MobileStore: concrete type that inherits index from Store
            # - OnlineStore: concrete type that inherits index from Store
            @physical_store_metadata, @mobile_store_metadata, @online_store_metadata, @store_metadata = object_type_metadata_for("PhysicalStore", "MobileStore", "OnlineStore", "Store") do |s|
              # PhysicalStore has its own direct index (does not inherit)
              s.object_type "PhysicalStore" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "address", "String"
                link_subtype_to_supertype(t, "Store")
                t.index "physical_stores"
              end

              # MobileStore and OnlineStore inherit index from Store abstract type
              s.object_type "MobileStore" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "app_url", "String"
                link_subtype_to_supertype(t, "Store")
              end

              s.object_type "OnlineStore" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "website", "String"
                link_subtype_to_supertype(t, "Store")
              end

              # Store abstract type (union or interface) with shared index
              s.public_send type_def_method, "Store" do |t|
                # Interfaces need fields defined
                if type_def_method == :interface_type
                  t.field "id", "ID!"
                  t.field "name", "String"
                end
                link_supertype_to_subtypes(t, "PhysicalStore", "MobileStore", "OnlineStore")
                t.index "stores"
              end
            end
          end

          describe "index_definition_names" do
            it "allows concrete types to inherit the index from their parent abstract type" do
              expect(mobile_store_metadata.index_definition_names).to eq ["stores"]
              expect(online_store_metadata.index_definition_names).to eq ["stores"]
            end

            it "allows concrete types with their own index to not inherit from the parent" do
              expect(physical_store_metadata.index_definition_names).to eq ["physical_stores"]
            end

            it "gives the parent abstract type its own index" do
              expect(store_metadata.index_definition_names).to eq ["stores"]
            end
          end

          describe "requires_typename_for_mixed_index" do
            it "is true for types that inherit an index (sharing a mixed-type index)" do
              expect(mobile_store_metadata.requires_typename_for_mixed_index).to eq true
              expect(online_store_metadata.requires_typename_for_mixed_index).to eq true
            end

            it "is false for types with their own direct index (single-type index)" do
              expect(physical_store_metadata.requires_typename_for_mixed_index).to eq false
            end

            it "is false for the parent abstract type with its own direct index" do
              expect(store_metadata.requires_typename_for_mixed_index).to eq false
            end
          end

          describe "update_targets data_params" do
            it "includes __typename for types that inherit an index (needed for type resolution in mixed-type indices)" do
              mobile_store_target = mobile_store_metadata.update_targets.find { |t| t.type == "MobileStore" }
              expect(mobile_store_target.data_params.keys).to include("__typename")
              expect(mobile_store_target.data_params["__typename"].source_path).to eq "__typename"

              online_store_target = online_store_metadata.update_targets.find { |t| t.type == "OnlineStore" }
              expect(online_store_target.data_params.keys).to include("__typename")
              expect(online_store_target.data_params["__typename"].source_path).to eq "__typename"
            end

            it "does not include __typename for types with their own direct index (single-type index doesn't need type resolution)" do
              physical_store_target = physical_store_metadata.update_targets.find { |t| t.type == "PhysicalStore" }
              expect(physical_store_target.data_params.keys).not_to include("__typename")
            end

            it "includes normal fields in data_params for types that inherit an index" do
              mobile_store_target = mobile_store_metadata.update_targets.find { |t| t.type == "MobileStore" }
              expect(mobile_store_target.data_params.keys).to include("name", "app_url")

              online_store_target = online_store_metadata.update_targets.find { |t| t.type == "OnlineStore" }
              expect(online_store_target.data_params.keys).to include("name", "website")
            end
          end

          describe "validation" do
            it "allows a concrete type to be a subtype of multiple abstract types as long as only one has an index" do
              widget_metadata = object_type_metadata_for("Widget") do |s|
                s.object_type "Widget" do |t|
                  t.field "id", "ID!"
                  t.field "name", "String"
                  link_subtype_to_supertype(t, "Named")
                  link_subtype_to_supertype(t, "Thing")
                end

                # Named has no index
                s.public_send type_def_method, "Named" do |t|
                  t.field "name", "String" if type_def_method == :interface_type
                  link_supertype_to_subtypes(t, "Widget")
                end

                # Thing has an index
                s.public_send type_def_method, "Thing" do |t|
                  t.field "id", "ID!" if type_def_method == :interface_type
                  link_supertype_to_subtypes(t, "Widget")
                  t.index "things"
                end
              end

              expect(widget_metadata.index_definition_names).to eq ["things"]
              expect(widget_metadata.requires_typename_for_mixed_index).to eq true
            end
          end
        end
      end

      describe "transitive interface inheritance" do
        it "allows a concrete type to inherit an index from a grandparent interface" do
          gadget_metadata = object_type_metadata_for("Gadget") do |s|
            # Gadget implements InterfaceA
            s.object_type "Gadget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "category", "String"
              t.implements "InterfaceA"
            end

            # InterfaceA implements InterfaceB (with the index)
            s.interface_type "InterfaceA" do |t|
              t.field "name", "String"
              t.field "category", "String"
              t.implements "InterfaceB"
            end

            # InterfaceB has the index
            s.interface_type "InterfaceB" do |t|
              t.field "name", "String"
              t.index "indexed_interfaces"
            end
          end

          expect(gadget_metadata.index_definition_names).to eq ["indexed_interfaces"]
          expect(gadget_metadata.requires_typename_for_mixed_index).to eq true
        end
      end
    end
  end
end
