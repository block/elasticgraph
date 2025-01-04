# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "index_mappings_spec_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "Datastore config index mappings -- abstract types" do
      include_context "IndexMappingsSpecSupport"

      shared_examples_for "a type with subtypes" do |type_def_method|
        context "composed of 2 indexed types" do
          it "generates separate mappings for the two subtypes" do
            widget_mapping, component_mapping = index_mappings_for "widgets", "components" do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "amount_cents", "Int"
                link_subtype_to_supertype(t, "Thing")
                t.index "widgets"
              end

              s.object_type "Component" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "weight", "Int"
                link_subtype_to_supertype(t, "Thing")
                t.index "components"
              end

              s.public_send type_def_method, "Thing" do |t|
                link_supertype_to_subtypes(t, "Widget", "Component")
              end
            end

            expect(widget_mapping.dig("properties")).to include({
              "id" => {"type" => "keyword"},
              "name" => {"type" => "keyword"},
              "amount_cents" => {"type" => "integer"}
            }).and exclude("weight")

            expect(component_mapping.dig("properties")).to include({
              "id" => {"type" => "keyword"},
              "name" => {"type" => "keyword"},
              "weight" => {"type" => "integer"}
            }).and exclude("amount_cents")
          end
        end

        context "that is itself indexed" do
          it "merges the subfields of the two types, and adds a __typename field to distinguish the subtype" do
            mapping = index_mapping_for "things" do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "amount_cents", "Int"
                link_subtype_to_supertype(t, "Thing")
              end

              s.object_type "Component" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "weight", "Int"
                link_subtype_to_supertype(t, "Thing")
              end

              s.public_send type_def_method, "Thing" do |t|
                link_supertype_to_subtypes(t, "Widget", "Component")
                t.index "things"
              end
            end

            expect(mapping.dig("properties")).to include({
              "id" => {"type" => "keyword"},
              "name" => {"type" => "keyword"},
              "amount_cents" => {"type" => "integer"},
              "weight" => {"type" => "integer"},
              "__typename" => {"type" => "keyword"}
            })
          end

          it "handles the subtypes having no fields" do
            mapping = index_mapping_for "things" do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                link_subtype_to_supertype(t, "Thing")
              end

              s.object_type "Component" do |t|
                t.field "id", "ID"
                link_subtype_to_supertype(t, "Thing")
              end

              s.public_send type_def_method, "Thing" do |t|
                link_supertype_to_subtypes(t, "Widget", "Component")
                t.index "things"
              end
            end

            expect(mapping.dig("properties")).to include({
              "__typename" => {"type" => "keyword"}
            })
          end

          it "raises an error if there is a common subfield with different mapping settings" do
            expect {
              index_mapping_for "things" do |s|
                s.object_type "Widget" do |t|
                  t.field "id", "ID!"
                  t.field "name", "String!" do |f|
                    f.mapping null_value: ""
                  end
                  link_subtype_to_supertype(t, "Thing")
                end

                s.object_type "Component" do |t|
                  t.field "id", "ID!"
                  t.field "name", "String!" do |f|
                    f.mapping null_value: "[null]"
                  end
                  link_subtype_to_supertype(t, "Thing")
                end

                s.object_type "Animal" do |t|
                  t.field "species", "String!"
                  link_subtype_to_supertype(t, "Thing")
                end

                s.public_send type_def_method, "Thing" do |t|
                  link_supertype_to_subtypes(t, "Widget", "Component", "Animal")
                  t.index "things"
                end
              end
            }.to raise_error(Errors::SchemaError, a_string_including("Conflicting definitions", "field `name`", "subtypes of `Thing`", "Widget", "Component").and(excluding("Animal")))
          end

          it "raises an error if there is a common subfield with different mapping types" do
            expect {
              index_mapping_for "things" do |s|
                s.object_type "Widget" do |t|
                  t.field "id", "ID!"
                  t.field "owner_id", "String"
                  link_subtype_to_supertype(t, "Thing")
                end

                s.object_type "Component" do |t|
                  t.field "id", "ID!"
                  t.field "owner_id", "Int"
                  link_subtype_to_supertype(t, "Thing")
                end

                s.object_type "Animal" do |t|
                  t.field "species", "String!"
                  link_subtype_to_supertype(t, "Thing")
                end

                s.public_send type_def_method, "Thing" do |t|
                  link_supertype_to_subtypes(t, "Widget", "Component", "Animal")
                  t.index "things"
                end
              end
            }.to raise_error(Errors::SchemaError, a_string_including(
              "Conflicting definitions",
              "field `owner_id`",
              "subtypes of `Thing`",
              "Widget",
              "Component",
              inspect_output_of('"type" => "keyword"'),
              inspect_output_of('"type" => "integer"')
            ).and(excluding("Animal")))
          end

          it "allows the different mapping setting issue to be resolved by configuring a different index field name for one field" do
            mapping = index_mapping_for "things" do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String!", name_in_index: "name_w" do |f|
                  f.mapping null_value: ""
                end
                link_subtype_to_supertype(t, "Thing")
              end

              s.object_type "Component" do |t|
                t.field "id", "ID!"
                t.field "name", "String!" do |f|
                  f.mapping null_value: "[null]"
                end
                link_subtype_to_supertype(t, "Thing")
              end

              s.public_send type_def_method, "Thing" do |t|
                link_supertype_to_subtypes(t, "Widget", "Component")
                t.index "things"
              end
            end

            expect(mapping.dig("properties")).to include({
              "id" => {"type" => "keyword"},
              "name" => {"type" => "keyword", "null_value" => "[null]"},
              "name_w" => {"type" => "keyword", "null_value" => ""},
              "__typename" => {"type" => "keyword"}
            })
          end
        end

        context "that is an embedded type" do
          it "merges the subfields of the two types, and adds a __typename field to distinguish the subtype" do
            mapping = index_mapping_for "my_type" do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "amount_cents", "Int"
                link_subtype_to_supertype(t, "Thing")
              end

              s.object_type "Component" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "weight", "Int"
                link_subtype_to_supertype(t, "Thing")
              end

              s.public_send type_def_method, "Thing" do |t|
                link_supertype_to_subtypes(t, "Widget", "Component")
              end

              s.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "thing", "Thing"
                t.index "my_type"
              end
            end

            expect(mapping.dig("properties", "thing")).to eq({
              "properties" => {
                "id" => {"type" => "keyword"},
                "name" => {"type" => "keyword"},
                "amount_cents" => {"type" => "integer"},
                "weight" => {"type" => "integer"},
                "__typename" => {"type" => "keyword"}
              }
            })
          end
        end
      end

      context "on a type union" do
        include_examples "a type with subtypes", :union_type do
          def link_subtype_to_supertype(object_type, supertype_name)
            # nothing to do; the linkage happens via a `subtypes` call on the supertype
          end

          def link_supertype_to_subtypes(union_type, *subtype_names)
            union_type.subtypes(*subtype_names)
          end
        end
      end

      context "on an interface type" do
        include_examples "a type with subtypes", :interface_type do
          def link_subtype_to_supertype(object_type, interface_name)
            object_type.implements interface_name
          end

          def link_supertype_to_subtypes(interface_type, *subtype_names)
            # nothing to do; the linkage happens via an `implements` call on the subtype
          end
        end

        it "ignores it if it has no subtypes" do
          mappings = index_mappings_for do |s|
            s.interface_type "Thing" do |t|
            end
          end

          expect(mappings).to be_empty
        end

        it "supports a subtype recursion (e.g. an interface that implements an interface)" do
          mapping = index_mapping_for "things" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String!"
              t.field "amount_cents", "Int!"
              t.implements "WidgetOrComponent"
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.field "name", "String!"
              t.field "weight", "Int!"
              t.implements "WidgetOrComponent"
            end

            s.interface_type "WidgetOrComponent" do |t|
              t.implements "Thing"
            end

            s.object_type "Object" do |t|
              t.field "id", "ID!"
              t.field "description", "String!"
              t.implements "Thing"
            end

            s.interface_type "Thing" do |t|
              t.index "things"
            end
          end

          expect(mapping.dig("properties")).to include({
            "id" => {"type" => "keyword"},
            "name" => {"type" => "keyword"},
            "amount_cents" => {"type" => "integer"},
            "weight" => {"type" => "integer"},
            "description" => {"type" => "keyword"},
            "__typename" => {"type" => "keyword"}
          })
        end
      end
    end
  end
end
