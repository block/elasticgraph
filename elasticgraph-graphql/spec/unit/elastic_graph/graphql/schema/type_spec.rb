# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/schema/type"
require "elastic_graph/graphql/schema"

module ElasticGraph
  class GraphQL
    class Schema
      RSpec.describe Type, :ensure_no_orphaned_types do
        it "exposes the name as a capitalized symbol" do
          type = define_schema do |schema|
            schema.object_type "Color"
          end.type_named("Color")

          expect(type.name).to eq :Color
        end

        it "inspects well" do
          type = define_schema do |schema|
            schema.object_type "Color"
          end.type_named("Color")

          expect(type.inspect).to eq "#<ElasticGraph::GraphQL::Schema::Type Color>"
        end

        describe "predicates and type wrapping" do
          attr_reader :schema

          before(:context) do
            # The examples in this example group all depend on this schema, so build it once,
            # and reuse it in each example. Schemas are immutable so this is no danger of having
            # a subtle ordering dependency.
            @schema = define_schema(clients_by_name: {}) do |schema|
              schema.object_type "Color" do |t|
                t.field "id", "ID"
                t.implements "EmbeddedInterface"
                t.field "name", "String"
              end

              schema.object_type "Velocity" do |t|
                t.field "id", "ID"
                t.implements "DirectlyIndexedInterface"
                t.field "name", "String"
              end

              schema.union_type "Attribute" do |t|
                t.subtypes "Color", "Velocity"
              end

              schema.union_type "IndexedAttribute" do |t|
                t.subtypes "Color", "Velocity"
                t.index "attributes"
              end

              schema.interface_type "EmbeddedInterface" do |t|
                t.field "name", "String"
              end

              schema.interface_type "DirectlyIndexedInterface" do |t|
                t.field "id", "ID"
                t.field "name", "String"
                t.index "direct_index"
              end

              schema.interface_type "IndirectlyIndexedInterface" do |t|
                t.field "name", "String"
              end

              schema.object_type "Person" do |t|
                t.implements "IndirectlyIndexedInterface"
                t.field "id", "ID!"
                t.field "name", "String"
                t.index "people"
              end

              schema.object_type "Photo" do |t|
                t.field "id", "ID!"
                t.index "photos"
              end

              schema.union_type "Entity" do |t|
                t.subtypes "Person", "Photo"
              end

              schema.enum_type "Size" do |t|
                t.values "small", "medium", "large"
              end

              schema.enum_type "Length" do |t|
                t.value "long"
                t.value "short"
              end

              schema.object_type "ColorEdge" do |t|
                t.field "cursor", "String"
                t.field "node", "Color!"
              end

              schema.object_type "WrappedTypes" do |t|
                t.field "int", "Int"
                t.field "non_null_int", "Int!"
                t.field "list_of_int", "[Int]"
                t.field "list_of_non_null_int", "[Int!]"
                t.field "non_null_list_of_int", "[Int]!"
                t.field "non_null_list_of_non_null_int", "[Int!]!"
                t.field "relay_connection", "PersonConnection", filterable: false, groupable: false
                t.field "non_null_relay_connection", "PersonConnection!", filterable: false, groupable: false
                t.field "relay_edge", "PersonEdge", filterable: false, groupable: false
                t.field "non_null_relay_edge", "PersonEdge!", filterable: false, groupable: false
                t.field "color", "Color"
                t.field "person", "Person"
                t.field "size", "Size"
                t.field "non_null_size", "Size!"
                t.field "list_of_size", "[Size]"
                t.field "non_null_person", "Person!" do |f|
                  f.mapping type: "object"
                end
                t.field "person_list", "[Person]" do |f|
                  f.mapping type: "object"
                end
                t.field "non_null_color", "Color!"
                t.field "attribute", "Attribute"
                t.field "indexed_attribute", "IndexedAttribute"
                t.field "non_null_attribute", "Attribute!"
                t.field "entity", "Entity"
                t.field "non_null_entity", "Entity!"
                t.field "indexed_aggregation", "PersonAggregation", filterable: false, groupable: false
                t.field "non_null_indexed_aggregation", "PersonAggregation!", filterable: false, groupable: false
                t.field "list_of_indexed_aggregation", "[PersonAggregation]", filterable: false, groupable: false do |f|
                  f.mapping type: "object"
                end
                t.field "non_null_list_of_indexed_aggregation", "[PersonAggregation]!", filterable: false, groupable: false do |f|
                  f.mapping type: "object"
                end

                t.field "id", "ID"
                t.index "wrapped_types"
              end
            end
          end

          it "can model a scalar" do
            type = type_for(:int)

            expect(type.name).to eq :Int
            expect(type).to only_satisfy_predicates(:nullable?)
            expect(type.unwrap_fully).to be schema.type_named(:Int)
            expect(type.unwrap_non_null).to be type
          end

          it "can model a non-nullable scalar" do
            type = type_for(:non_null_int)

            expect(type.name).to eq :Int!
            expect(type).to only_satisfy_predicates(:non_null?)
            expect(type.unwrap_fully).to be schema.type_named(:Int)
            expect(type.unwrap_non_null).to be schema.type_named(:Int)
          end

          it "can model an embedded object" do
            type = type_for(:color)

            expect(type.name).to eq :Color
            expect(type).to only_satisfy_predicates(:nullable?, :object?, :embedded_object?)
            expect(type.unwrap_fully).to be schema.type_named(:Color)
            expect(type.unwrap_non_null).to be type
          end

          it "can model a non-nullable embedded object" do
            type = type_for(:non_null_color)

            expect(type.name).to eq :Color!
            expect(type).to only_satisfy_predicates(:non_null?, :object?, :embedded_object?)
            expect(type.unwrap_fully).to be schema.type_named(:Color)
            expect(type.unwrap_non_null).to be schema.type_named(:Color)
          end

          it "can model a list" do
            type = type_for(:list_of_int)

            expect(type.name).to eq :"[Int]"
            expect(type).to only_satisfy_predicates(:nullable?, :list?, :collection?)
            expect(type.unwrap_fully).to be schema.type_named(:Int)
            expect(type.unwrap_non_null).to be type
          end

          it "can model a relay connection" do
            type = type_for(:relay_connection)

            expect(type.name).to eq :PersonConnection
            expect(type).to only_satisfy_predicates(:nullable?, :object?, :relay_connection?, :collection?)
            expect(type.unwrap_fully).to be schema.type_named(:Person)
            expect(type.unwrap_non_null).to be type
          end

          it "can model a non-nullable relay connection" do
            type = type_for(:non_null_relay_connection)

            expect(type.name).to eq :PersonConnection!
            expect(type).to only_satisfy_predicates(:non_null?, :object?, :relay_connection?, :collection?)
            expect(type.unwrap_fully).to be schema.type_named(:Person)
            expect(type.unwrap_non_null).to be schema.type_named(:PersonConnection)
          end

          it "can model a relay edge" do
            type = type_for(:relay_edge)

            expect(type.name).to eq :PersonEdge
            expect(type).to only_satisfy_predicates(:nullable?, :object?, :relay_edge?)
            expect(type.unwrap_fully).to be schema.type_named(:PersonEdge)
            expect(type.unwrap_non_null).to be type
          end

          it "can model a non-nullable relay edge" do
            type = type_for(:non_null_relay_edge)

            expect(type.name).to eq :PersonEdge!
            expect(type).to only_satisfy_predicates(:non_null?, :object?, :relay_edge?)
            expect(type.unwrap_fully).to be schema.type_named(:PersonEdge)
            expect(type.unwrap_non_null).to be schema.type_named(:PersonEdge)
          end

          it "can model a list of non-nullable scalars" do
            type = type_for(:list_of_non_null_int)

            expect(type.name).to eq :"[Int!]"
            expect(type).to only_satisfy_predicates(:nullable?, :list?, :collection?)
            expect(type.unwrap_fully).to be schema.type_named(:Int)
            expect(type.unwrap_non_null).to be type
          end

          it "can model a non-nullable list of scalars" do
            type = type_for(:non_null_list_of_int)

            expect(type.name).to eq :"[Int]!"
            expect(type).to only_satisfy_predicates(:non_null?, :list?, :collection?)
            expect(type.unwrap_fully).to be schema.type_named(:Int)
            expect(type.unwrap_non_null.name).to eq :"[Int]"
          end

          it "can model a non-nullable list of non-nullable scalars" do
            type = type_for(:non_null_list_of_non_null_int)

            expect(type.name).to eq :"[Int!]!"
            expect(type).to only_satisfy_predicates(:non_null?, :list?, :collection?)
            expect(type.unwrap_fully).to be schema.type_named(:Int)
            expect(type.unwrap_non_null.name).to eq :"[Int!]"
          end

          it "can model an indexed type" do
            type = type_for(:person)

            expect(type.name).to eq :Person
            expect(type).to only_satisfy_predicates(:nullable?, :object?, :indexed_document?)
            expect(type.unwrap_fully).to be schema.type_named(:Person)
            expect(type.unwrap_non_null).to be type
          end

          it "can model an indexed aggregation type" do
            type = type_for(:indexed_aggregation)

            expect(type.name).to eq :PersonAggregation
            expect(type).to only_satisfy_predicates(:nullable?, :object?, :indexed_aggregation?)
            expect(type.unwrap_fully).to be schema.type_named(:PersonAggregation)
            expect(type.unwrap_non_null).to be type
          end

          it "can model a non-null indexed aggregation type" do
            type = type_for(:non_null_indexed_aggregation)

            expect(type.name).to eq :PersonAggregation!
            expect(type).to only_satisfy_predicates(:non_null?, :object?, :indexed_aggregation?)
            expect(type.unwrap_fully).to be schema.type_named(:PersonAggregation)
            expect(type.unwrap_non_null.name).to be :PersonAggregation
          end

          it "can model a list of indexed aggregation type" do
            type = type_for(:list_of_indexed_aggregation)

            expect(type.name).to eq :"[PersonAggregation]"
            expect(type).to only_satisfy_predicates(:nullable?, :list?, :collection?)
            expect(type.unwrap_fully).to be schema.type_named(:PersonAggregation)
            expect(type.unwrap_non_null.name).to be :"[PersonAggregation]"
          end

          it "can model a non-null list of indexed aggregation type" do
            type = type_for(:non_null_list_of_indexed_aggregation)

            expect(type.name).to eq :"[PersonAggregation]!"
            expect(type).to only_satisfy_predicates(:non_null?, :list?, :collection?)
            expect(type.unwrap_fully).to be schema.type_named(:PersonAggregation)
            expect(type.unwrap_non_null.name).to be :"[PersonAggregation]"
          end

          it "can model a list of indexed type" do
            type = type_for(:person_list)

            expect(type.name).to eq :"[Person]"
            expect(type).to only_satisfy_predicates(:nullable?, :list?, :collection?)
            expect(type.unwrap_fully).to be schema.type_named(:Person)
            expect(type.unwrap_non_null).to be type
          end

          it "can model a non-nullable indexed type" do
            type = type_for(:non_null_person)

            expect(type.name).to eq :Person!
            expect(type).to only_satisfy_predicates(:non_null?, :object?, :indexed_document?)
            expect(type.unwrap_fully).to be schema.type_named(:Person)
            expect(type.unwrap_non_null).to be schema.type_named(:Person)
          end

          it "can model a union of embedded object types" do
            type = type_for(:attribute)

            expect(type.name).to eq :Attribute
            expect(type).to only_satisfy_predicates(:nullable?, :object?, :abstract?, :embedded_object?)
            expect(type.unwrap_fully).to be schema.type_named(:Attribute)
            expect(type.unwrap_non_null).to be type
          end

          it "can model an indexed union of object types" do
            type = type_for(:indexed_attribute)

            expect(type.name).to eq :IndexedAttribute
            expect(type).to only_satisfy_predicates(:nullable?, :object?, :abstract?, :indexed_document?)
            expect(type.unwrap_fully).to be schema.type_named(:IndexedAttribute)
            expect(type.unwrap_non_null).to be type
          end

          it "can model a non-nullable union of embedded object types" do
            type = type_for(:non_null_attribute)

            expect(type.name).to eq :Attribute!
            expect(type).to only_satisfy_predicates(:non_null?, :object?, :abstract?, :embedded_object?)
            expect(type.unwrap_fully).to be schema.type_named(:Attribute)
            expect(type.unwrap_non_null).to be schema.type_named(:Attribute)
          end

          it "can model a union of indexed object types" do
            type = type_for(:entity)

            expect(type.name).to eq :Entity
            expect(type).to only_satisfy_predicates(:nullable?, :object?, :abstract?, :indexed_document?)
            expect(type.unwrap_fully).to be schema.type_named(:Entity)
            expect(type.unwrap_non_null).to be type
          end

          it "can model a non-null union of indexed object types" do
            type = type_for(:non_null_entity)

            expect(type.name).to eq :Entity!
            expect(type).to only_satisfy_predicates(:non_null?, :object?, :abstract?, :indexed_document?)
            expect(type.unwrap_fully).to be schema.type_named(:Entity)
            expect(type.unwrap_non_null).to be schema.type_named(:Entity)
          end

          it "can model an enum type" do
            type = type_for(:size)

            expect(type.name).to eq :Size
            expect(type).to only_satisfy_predicates(:nullable?, :enum?)
            expect(type.unwrap_fully).to be type
            expect(type.unwrap_non_null).to be type
          end

          it "can model a non-null enum type" do
            type = type_for(:non_null_size)

            expect(type.name).to eq :Size!
            expect(type).to only_satisfy_predicates(:non_null?, :enum?)
            expect(type.unwrap_fully).to be schema.type_named(:Size)
            expect(type.unwrap_non_null).to be schema.type_named(:Size)
          end

          it "can model a list of enums" do
            type = type_for(:list_of_size)

            expect(type.name).to eq :"[Size]"
            expect(type).to only_satisfy_predicates(:nullable?, :list?, :collection?)
            expect(type.unwrap_fully).to be schema.type_named(:Size)
            expect(type.unwrap_non_null).to be type
          end

          it "can model an input type" do
            type = schema.type_named(:IntFilterInput)

            expect(type.name).to eq :IntFilterInput
            expect(type).to only_satisfy_predicates(:nullable?, :object?)
            expect(type.unwrap_fully).to be type
            expect(type.unwrap_non_null).to be type
          end

          it "can model an embedded interface type" do
            type = schema.type_named(:EmbeddedInterface)

            expect(type.name).to eq :EmbeddedInterface
            expect(type).to only_satisfy_predicates(:nullable?, :object?, :embedded_object?, :abstract?)
            expect(type.unwrap_fully).to be type
            expect(type.unwrap_non_null).to be type
          end

          it "can model a directly indexed interface type" do
            type = schema.type_named(:DirectlyIndexedInterface)

            expect(type.name).to eq :DirectlyIndexedInterface
            expect(type).to only_satisfy_predicates(:nullable?, :object?, :indexed_document?, :abstract?)
            expect(type.unwrap_fully).to be type
            expect(type.unwrap_non_null).to be type
          end

          it "can model an indirectly indexed interface type" do
            type = schema.type_named(:IndirectlyIndexedInterface)

            expect(type.name).to eq :IndirectlyIndexedInterface
            expect(type).to only_satisfy_predicates(:nullable?, :object?, :indexed_document?, :abstract?)
            expect(type.unwrap_fully).to be type
            expect(type.unwrap_non_null).to be type
          end

          predicates = %i[nullable? non_null? list? object? embedded_object? indexed_document? indexed_aggregation? relay_connection? relay_edge? abstract? collection? enum?]
          matcher :only_satisfy_predicates do |*expected_predicates|
            match do |type|
              @satisfied_predicates = predicates.select { |p| type.public_send(p) }
              @satisfied_predicates.sort == expected_predicates.sort
            end

            # :nocov: -- only executed on a test failure
            failure_message do |type|
              parts = [message_part("expected #{type.inspect} to only satisfy", expected_predicates)]

              failed_to_satisfy_predicates = expected_predicates - @satisfied_predicates
              if failed_to_satisfy_predicates.any?
                parts << [message_part("It failed to satisfy", failed_to_satisfy_predicates)]
              end

              extra_satisfied_predicates = @satisfied_predicates - expected_predicates
              if extra_satisfied_predicates.any?
                parts << [message_part("It also satisfied", extra_satisfied_predicates)]
              end

              parts.join("\n\n")
            end

            def message_part(intro, predicates)
              "#{intro}:\n\n  - #{predicates.join("\n  - ")}"
            end
            # :nocov:
          end

          def type_for(field_name)
            schema.field_named(:WrappedTypes, field_name).type
          end
        end

        describe "#enum_value_named" do
          let(:schema) do
            define_schema do |schema|
              schema.enum_type "ColorSpace" do |t|
                t.values "rgb", "srgb"
              end
            end
          end

          it "returns the same enum_value object returns by schema's `enum_value_named` method" do
            from_type = schema.type_named(:ColorSpace).enum_value_named(:rgb)
            from_schema = schema.enum_value_named(:ColorSpace, :rgb)

            expect(from_schema).to be_a(EnumValue).and be(from_type)
          end

          it "supports the enum_value being named with a string or symbol" do
            from_string = schema.type_named(:ColorSpace).enum_value_named("rgb")
            from_symbol = schema.type_named(:ColorSpace).enum_value_named(:rgb)

            expect(from_symbol).to be_a(EnumValue).and be(from_string)
          end
        end

        describe "#field_named" do
          let(:schema) do
            define_schema do |s|
              s.object_type "Color" do |t|
                t.field "red", "Int!"
              end
            end
          end

          it "returns the same field object returned from the schema's `field_named` method" do
            from_type = schema.type_named(:Color).field_named(:red)
            from_schema = schema.field_named(:Color, :red)

            expect(from_schema).to be_a(Field).and be(from_type)
          end

          it "supports the field being named with a string or symbol" do
            from_string = schema.type_named(:Color).field_named("red")
            from_symbol = schema.type_named(:Color).field_named(:red)

            expect(from_symbol).to be_a(Field).and be(from_string)
          end
        end

        describe "#abstract?" do
          let(:schema) do
            define_schema do |s|
              s.object_type "Color" do |t|
                t.field "red", "Int!"
              end

              s.object_type "Size" do |t|
                t.implements "Named"
                t.field "name", "String"
                t.field "small", "Int!"
              end

              s.object_type "Person" do |t|
                t.implements "Named"
                t.field "name", "String"
              end

              s.interface_type "Named" do |t|
                t.field "name", "String"
              end

              s.union_type "Options" do |t|
                t.subtypes "Color", "Size"
              end
            end
          end

          it "returns true for unions" do
            type = schema.type_named(:Options)
            expect(type.abstract?).to be true
          end

          it "returns true for interfaces" do
            type = schema.type_named(:Named)
            expect(type.abstract?).to be true
          end

          it "returns false for objects" do
            type = schema.type_named(:Size)
            expect(type.abstract?).to be false
          end

          it "returns false for scalars" do
            type = schema.type_named(:Int)
            expect(type.abstract?).to be false
          end
        end

        describe "#subtypes" do
          let(:schema) do
            define_schema do |s|
              s.object_type "Color" do |t|
                t.field "red", "Int!"
              end

              s.object_type "Size" do |t|
                t.implements "Named"
                t.field "name", "String"
                t.field "small", "Int!"
              end

              s.object_type "Person" do |t|
                t.implements "Named"
                t.field "name", "String"
              end

              s.interface_type "Named" do |t|
                t.field "name", "String"
              end

              s.union_type "Options" do |t|
                t.subtypes "Color", "Size"
              end
            end
          end

          it "returns [] for object types" do
            type = schema.type_named(:Size)
            expect(type.subtypes).to eq []
          end

          it "returns [] for scalar types" do
            type = schema.type_named(:Int)
            expect(type.subtypes).to eq []
          end

          it "returns the subtypes of a union" do
            type = schema.type_named(:Options)
            expect(type.subtypes).to contain_exactly(schema.type_named(:Color), schema.type_named(:Size))
          end

          it "returns the subtypes of an interface" do
            type = schema.type_named(:Named)
            expect(type.subtypes).to contain_exactly(schema.type_named(:Size), schema.type_named(:Person))
          end
        end

        describe "#search_index_definitions" do
          it "returns an empty array for a non-union type that is not indexed" do
            search_index_definitions = search_index_definitions_from do |schema, type|
              schema.object_type(type) {}
            end

            expect(search_index_definitions).to eq []
          end

          it "returns an array of one IndexDefinition object for a non-union indexed document type with one datastore index" do
            search_index_definitions = search_index_definitions_from do |schema, type|
              schema.object_type type do |t|
                t.field "id", "ID!"
                t.index "things"
              end
            end

            expect(search_index_definitions.map(&:class)).to eq [DatastoreCore::IndexDefinition::Index]
            expect(search_index_definitions.map(&:name)).to eq ["things"]
          end

          it "includes the index definitions from the subtypes when it is a type union of indexed document types" do
            search_index_definitions = search_index_definitions_from do |schema, type|
              schema.object_type "T1" do |t|
                t.field "id", "ID!"
                t.index "t1"
              end

              schema.object_type "T2" do |t|
                t.field "id", "ID!"
                t.index "t2"
              end

              schema.object_type "T3" do |t|
                t.field "id", "ID!"
                t.index "t3"
              end

              schema.object_type "T4" do |t|
                t.field "id", "ID!"
                t.index "t4"
              end

              schema.union_type type do |t|
                t.subtypes "T1", "T2", "T3", "T4"
                t.index "union_index"
              end
            end

            expect(search_index_definitions.map(&:name)).to contain_exactly("t1", "t2", "t3", "t4", "union_index")
          end

          it "deduplicates the index definitions before returning them" do
            search_index_definitions = search_index_definitions_from do |schema, type|
              schema.object_type "T1a" do |t|
                t.field "id", "ID!"
                t.index "t1"
              end

              schema.object_type "T2" do |t|
                t.field "id", "ID!"
                t.index "t2"
              end

              schema.object_type "T1b" do |t|
                t.field "id", "ID!"
                t.index "t1"
              end

              schema.object_type "T4" do |t|
                t.field "id", "ID!"
                t.index "t4"
              end

              schema.union_type type do |t|
                t.subtypes "T1a", "T2", "T1b", "T4"
                t.index "t4"
              end
            end

            expect(search_index_definitions.map(&:name)).to contain_exactly("t1", "t2", "t4")
          end

          context "on an indexed aggregation type" do
            it "returns the indices of the corresponding indexed document type" do
              search_index_definitions = search_index_definitions_from type_name: "ThingAggregation" do |schema|
                schema.object_type "Thing" do |t|
                  t.field "id", "ID!"
                  t.index "things"
                end
              end

              expect(search_index_definitions.map(&:class)).to eq [DatastoreCore::IndexDefinition::Index]
              expect(search_index_definitions.map(&:name)).to eq ["things"]
            end

            it "returns the set union of indices of the corresponding indexed union type when the source type is a union" do
              search_index_definitions = search_index_definitions_from type_name: "ThingAggregation" do |schema|
                schema.object_type "Entity" do |t|
                  t.field "id", "ID!"
                  t.index "entities"
                end

                schema.object_type "Gadget" do |t|
                  t.field "id", "ID!"
                  t.index "gadgets"
                end

                schema.union_type "Thing" do |t|
                  t.subtypes "Entity", "Gadget"
                end
              end

              expect(search_index_definitions.map(&:class)).to contain_exactly(DatastoreCore::IndexDefinition::Index, DatastoreCore::IndexDefinition::Index)
              expect(search_index_definitions.map(&:name)).to contain_exactly("entities", "gadgets")
            end
          end

          def search_index_definitions_from(type_name: :TheType)
            schema = define_schema do |s|
              yield s, type_name
            end

            schema.type_named(type_name).search_index_definitions
          end
        end

        describe "#hidden_from_queries?" do
          it "returns `false` on a type that has no backing indexed types" do
            schema = define_schema do |s|
              s.object_type "Color" do |t|
                t.field "name", "String"
              end
            end

            type = schema.type_named("Color")

            expect(type.hidden_from_queries?).to be false
          end

          it "returns `false` on a type that has all index definitions accessible from queries on its backing indexed types" do
            schema = define_schema(index_definitions: {
              "colors" => config_index_def_of(query_cluster: "main")
            }) do |s|
              s.object_type "Color" do |t|
                t.field "id", "ID!"
                t.index "colors"
              end
            end

            type = schema.type_named("Color")

            expect(type.hidden_from_queries?).to be false
          end

          it "returns `true` on a type that has all index definitions inaccessible from queries on its backing indexed types" do
            schema = define_schema(index_definitions: {
              "colors" => config_index_def_of(query_cluster: nil)
            }) do |s|
              s.object_type "Color" do |t|
                t.field "id", "ID!"
                t.index "colors"
              end
            end

            type = schema.type_named("Color")

            expect(type.hidden_from_queries?).to be true
          end

          it "returns `true` on an indexed aggregation type based on a source union type that has all indices inaccessible" do
            schema = define_schema(index_definitions: {
              "entities" => config_index_def_of(query_cluster: nil),
              "gadgets" => config_index_def_of(query_cluster: nil)
            }) do |s|
              s.object_type "Entity" do |t|
                t.field "id", "ID!"
                t.index "entities"
              end

              s.object_type "Gadget" do |t|
                t.field "id", "ID!"
                t.index "gadgets"
              end

              s.union_type "Thing" do |t|
                t.subtypes "Entity", "Gadget"
              end
            end

            expect(schema.type_named("ThingAggregation").hidden_from_queries?).to eq true
          end

          it "returns `false` on a type that has a mixture of accessible and inaccessible index definitions on its backing indexed types" do
            schema = define_schema(index_definitions: {
              "colors" => config_index_def_of(query_cluster: nil),
              "sizes" => config_index_def_of(query_cluster: "main")
            }) do |s|
              s.object_type "Color" do |t|
                t.field "id", "ID!"
                t.index "colors"
              end

              s.object_type "Size" do |t|
                t.field "id", "ID!"
                t.index "sizes"
              end

              s.union_type "ColorOrSize" do |t|
                t.subtypes "Color", "Size"
              end
            end

            color = schema.type_named("Color")
            size = schema.type_named("Size")
            color_or_size = schema.type_named("ColorOrSize")

            expect(color.hidden_from_queries?).to be true
            expect(size.hidden_from_queries?).to be false
            expect(color_or_size.hidden_from_queries?).to be false
          end
        end

        def define_schema(index_definitions: nil, **overrides, &schema_def)
          build_graphql(schema_definition: schema_def, index_definitions: index_definitions, **overrides).schema
        end
      end
    end
  end
end
