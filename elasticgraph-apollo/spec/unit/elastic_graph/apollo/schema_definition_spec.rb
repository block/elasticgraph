# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/apollo/schema_definition/api_extension"
require "elastic_graph/spec_support/runtime_metadata_support"
require "elastic_graph/spec_support/schema_definition_helpers"
require "graphql"

module ElasticGraph
  module Apollo
    RSpec.describe SchemaDefinition do
      include SchemaArtifacts::RuntimeMetadata::RuntimeMetadataSupport

      include_context "SchemaDefinitionHelpers"

      def self.with_both_casing_forms(&block)
        context "with schema elements configured to use camelCase" do
          let(:schema_element_name_form) { :camelCase }
          module_exec(&block)
        end

        context "with schema elements configured to use snake_case" do
          let(:schema_element_name_form) { :snake_case }
          module_exec(&block)
        end
      end

      with_both_casing_forms do
        let(:schema_elements) { SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: schema_element_name_form) }

        it "defines the static schema elements that must be present in every apollo subgraph schema" do
          schema_string = graphql_schema_string do |s|
            define_some_types_on(s)

            # Verify that calling `results` multiple times does not trigger duplicate definition errors.
            # (at one point it did).
            s.results
            s.results
          end

          expect(schema_string).to include(*SchemaDefinition::APIExtension::DIRECTIVE_DEFINITIONS_BY_FEDERATION_VERSION.fetch("2.6"))

          # Verify the 2.6 vs 2.0 differences.
          expect(schema_string).to include("federation/v2.6")
          expect(schema_string).to exclude("federation/v2.5")
          expect(schema_string).to exclude("federation/v2.3")
          expect(schema_string).to exclude("federation/v2.0")
          expect(schema_string).to include("@authenticated")
          expect(schema_string).to include("@composeDirective")
          expect(schema_string).to include("@interfaceObject")
          expect(schema_string).to include("@policy")
          expect(schema_string).to include("@requiresScope")

          expect(type_def_from(schema_string, "federation__Scope")).to eq("scalar federation__Scope")
          expect(type_def_from(schema_string, "federation__Policy")).to eq("scalar federation__Policy")
          expect(type_def_from(schema_string, "FieldSet")).to eq("scalar FieldSet")
          expect(type_def_from(schema_string, "link__Import")).to eq("scalar link__Import")

          expect(type_def_from(schema_string, "link__Purpose")).to eq(<<~EOS.strip)
            enum link__Purpose {
              EXECUTION
              SECURITY
            }
          EOS

          expect(type_def_from(schema_string, "_Any")).to eq("scalar _Any")
          expect(type_def_from(schema_string, "_Service")).to eq(<<~EOS.strip)
            type _Service {
              sdl: String
            }
          EOS
        end

        it "allows the older v2.5 apollo federation directives to be defined instead of the v2.6 ones" do
          schema_string = graphql_schema_string do |schema|
            schema.target_apollo_federation_version "2.5"
            define_some_types_on(schema)
          end

          expect(schema_string).to include(*SchemaDefinition::APIExtension::DIRECTIVE_DEFINITIONS_BY_FEDERATION_VERSION.fetch("2.5"))

          # verify the 2.5 vs 2.6 differences
          expect(schema_string).to include("federation/v2.5")
          expect(schema_string).to exclude("federation/v2.6")
          expect(schema_string).to exclude("federation/v2.3")
          expect(schema_string).to exclude("federation/v2.0")
          expect(schema_string).to exclude("@policy")

          # If an unsupported version is passed, the error includes a `v` in the formatting, so
          # users might try to configure it with that. Here we verify that that is supported.
          schema_string_with_v = graphql_schema_string do |schema|
            schema.target_apollo_federation_version "v2.5"
            define_some_types_on(schema)
          end

          expect(schema_string_with_v).to eq(schema_string)
        end

        it "allows the older v2.3 apollo federation directives to be defined instead of the v2.6 ones" do
          schema_string = graphql_schema_string do |schema|
            schema.target_apollo_federation_version "2.3"
            define_some_types_on(schema)
          end

          expect(schema_string).to include(*SchemaDefinition::APIExtension::DIRECTIVE_DEFINITIONS_BY_FEDERATION_VERSION.fetch("2.3"))

          # verify the 2.3 vs 2.6 differences
          expect(schema_string).to include("federation/v2.3")
          expect(schema_string).to exclude("federation/v2.6")
          expect(schema_string).to exclude("federation/v2.5")
          expect(schema_string).to exclude("federation/v2.0")
          expect(schema_string).to exclude("@authenticated")
          expect(schema_string).to exclude("@policy")
          expect(schema_string).to exclude("@requiresScope")

          # If an unsupported version is passed, the error includes a `v` in the formatting, so
          # users might try to configure it with that. Here we verify that that is supported.
          schema_string_with_v = graphql_schema_string do |schema|
            schema.target_apollo_federation_version "v2.3"
            define_some_types_on(schema)
          end

          expect(schema_string_with_v).to eq(schema_string)
        end

        it "allows the older v2.0 apollo federation directives to be defined instead of the v2.6 ones" do
          schema_string = graphql_schema_string do |schema|
            schema.target_apollo_federation_version "2.0"
            define_some_types_on(schema)
          end

          expect(schema_string).to include(*SchemaDefinition::APIExtension::DIRECTIVE_DEFINITIONS_BY_FEDERATION_VERSION.fetch("2.0"))

          # verify the 2.0 vs 2.6 differences
          expect(schema_string).to include("federation/v2.0")
          expect(schema_string).to exclude("federation/v2.6")
          expect(schema_string).to exclude("federation/v2.5")
          expect(schema_string).to exclude("federation/v2.3")
          expect(schema_string).to exclude("@authenticated")
          expect(schema_string).to exclude("@composeDirective")
          expect(schema_string).to exclude("@interfaceObject")
          expect(schema_string).to exclude("@policy")
          expect(schema_string).to exclude("@requiresScope")

          # If an unsupported version is passed, the error includes a `v` in the formatting, so
          # users might try to configure it with that. Here we verify that that is supported.
          schema_string_with_v = graphql_schema_string do |schema|
            schema.target_apollo_federation_version "v2.0"
            define_some_types_on(schema)
          end

          expect(schema_string_with_v).to eq(schema_string)
        end

        it "raises a clear error if the user tries to target an unsupported apollo federation version" do
          expect {
            graphql_schema_string do |schema|
              schema.target_apollo_federation_version "1.75"
            end
          }.to raise_error Errors::SchemaError, a_string_including("does not support Apollo federation v1.75. Pick one of the supported versions")

          expect {
            graphql_schema_string do |schema|
              schema.target_apollo_federation_version "v1.75"
            end
          }.to raise_error Errors::SchemaError, a_string_including("does not support Apollo federation v1.75. Pick one of the supported versions")
        end

        it 'adds a `@key(fields: "id")` directive to each indexed type and includes them in the `_Entity` union (but not to embedded object types)' do
          schema_string = graphql_schema_string { |s| define_some_types_on(s) }

          expect(type_def_from(schema_string, "IndexedType1")).to eq(<<~EOS.strip)
            type IndexedType1 @key(fields: "id") {
              embedded: EmbeddedObjectType1
              graphql: String
              id: ID!
              num: Int
            }
          EOS

          expect(type_def_from(schema_string, "IndexedType2")).to eq(<<~EOS.strip)
            type IndexedType2 @key(fields: "id") {
              id: ID!
            }
          EOS

          expect(type_def_from(schema_string, "EmbeddedObjectType1")).to eq(<<~EOS.strip)
            type EmbeddedObjectType1 {
              id: ID!
            }
          EOS

          expect(type_def_from(schema_string, "_Entity")).to eq("union _Entity = IndexedType1 | IndexedType2")
        end

        it 'omits the `@key(fields: "id")` directive when the `id` field is indexing-only, since key fields must be GraphQL fields' do
          schema_string = graphql_schema_string { |s| define_some_types_on(s, id_is_indexing_only: ["IndexedType2"]) }

          expect(type_def_from(schema_string, "IndexedType1").lines.first.strip).to eq("type IndexedType1 @key(fields: \"id\") {")
          expect(type_def_from(schema_string, "IndexedType2").lines.first.strip).to eq("type IndexedType2 {")

          expect(type_def_from(schema_string, "_Entity")).to eq("union _Entity = IndexedType1")
        end

        it "adds object types that have resolvable apollo keys to the Entity union" do
          schema_string = graphql_schema_string do |schema|
            schema.object_type "IndexedType1" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.index "index1"
            end

            schema.object_type "UnindexedType1" do |t|
              t.field "id", "ID!"
              t.field "key", "KeyType!"
              t.apollo_key fields: "id key { nestedKey { id } }", resolvable: true
              t.field "name", "String" do |f|
                f.apollo_external
              end
            end

            schema.object_type "UnindexedType2" do |t|
              t.field "id", "ID!"
              t.apollo_key fields: "id", resolvable: false
            end

            schema.object_type "UnindexedType3" do |t|
              t.field "id", "ID!"
            end

            schema.object_type "UnindexedType4" do |t|
              t.field "id", "ID!"
              t.directive "key", fields: "id"
            end

            schema.object_type "KeyType" do |t|
              t.field "nestedKey", "NestedKeyType"
            end
            schema.object_type "NestedKeyType" do |t|
              t.field "id", "ID!"
            end
          end

          expect(type_def_from(schema_string, "UnindexedType1")).to eq(<<~EOS.strip)
            type UnindexedType1 @key(fields: "id key { nestedKey { id } }") {
              id: ID!
              key: KeyType!
              name: String @external
            }
          EOS

          expect(type_def_from(schema_string, "_Entity")).to eq("union _Entity = IndexedType1 | UnindexedType1 | UnindexedType4")
        end

        it "raises a clear error when an unindexed resolvable entity types have fields that aren't key fields, relationships, or apollo_external fields" do
          expect {
            define_unindexed_types do |t|
              t.apollo_key fields: "id key { keyType { field1 } }"
            end
          }.to raise_error Errors::SchemaError, a_string_including(
            "`UnindexedType1` has fields",
            "`UnindexedType2` has fields",
            "unable to resolve",
            "* `field1`", "* `field2`"
          )

          expect {
            define_unindexed_types do |t|
              t.directive "key", fields: "id key { keyType { field1 } }"
            end
          }.to raise_error Errors::SchemaError, a_string_including(
            "`UnindexedType1` has fields",
            "`UnindexedType2` has fields",
            "unable to resolve",
            "* `field1`", "* `field2`"
          )
        end

        it "allows non-key, non-relationship, non-external fields on an unindexed entity type when it has `resolvable: false`" do
          expect {
            define_unindexed_types do |t|
              t.apollo_key fields: "id key { keyType { field1 } }", resolvable: false
            end
          }.not_to raise_error
        end

        it "avoids including indexed interfaces in the `_Entity` union (and does not add `@key` to it) since unions can't include interfaces" do
          schema_string = graphql_schema_string do |schema|
            schema.object_type "IndexedType1" do |t|
              t.implements "NamedEntity"
              t.field "graphql", "String", name_in_index: "index"
              t.field "id", "ID!"
              t.field "name", "String"
              t.index "index1"
            end

            schema.object_type "IndexedType2" do |t|
              t.implements "NamedEntity"
              t.field "id", "ID!"
              t.field "name", "String"
              t.index "index1"
            end

            schema.interface_type "NamedEntity" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
            end
          end

          expect(type_def_from(schema_string, "IndexedType1")).to eq(<<~EOS.strip)
            type IndexedType1 implements NamedEntity @key(fields: "id") {
              graphql: String
              id: ID!
              name: String
            }
          EOS

          expect(type_def_from(schema_string, "IndexedType2")).to eq(<<~EOS.strip)
            type IndexedType2 implements NamedEntity @key(fields: "id") {
              id: ID!
              name: String
            }
          EOS

          expect(type_def_from(schema_string, "NamedEntity")).to eq(<<~EOS.strip)
            interface NamedEntity {
              id: ID!
              name: String
            }
          EOS

          expect(type_def_from(schema_string, "_Entity")).to eq("union _Entity = IndexedType1 | IndexedType2")
        end

        it "has no problem with the different entity subtypes having fields with the same names and different types, mappings, etc" do
          schema_string = graphql_schema_string do |schema|
            schema.object_type "IndexedType1" do |t|
              t.field "id", "ID!" do |f|
                f.mapping null_value: ""
              end
              t.index "index1"
            end

            schema.object_type "IndexedType2" do |t|
              t.field "id", "String!" do |f|
                f.mapping null_value: "(missing)"
              end
              t.index "index2"
            end
          end

          expect(type_def_from(schema_string, "IndexedType1")).to eq(<<~EOS.strip)
            type IndexedType1 @key(fields: "id") {
              id: ID!
            }
          EOS

          expect(type_def_from(schema_string, "IndexedType2")).to eq(<<~EOS.strip)
            type IndexedType2 @key(fields: "id") {
              id: String!
            }
          EOS

          expect(type_def_from(schema_string, "_Entity")).to eq("union _Entity = IndexedType1 | IndexedType2")
        end

        it "defines the fields required by apollo on the `Query` type" do
          schema_string = graphql_schema_string { |s| define_some_types_on(s) }

          expect(type_def_from(schema_string, "Query")[/\A.*_Service!/m]).to eq(<<~EOS.strip)
            type Query {
              _entities(
                representations: [_Any!]!
              ): [_Entity]!
              _service: _Service!
          EOS
        end

        it "avoids defining `_Entity` and `Query._entities` if there are no indexed types (as per the apollo spec)" do
          schema_string = graphql_schema_string { |s| define_some_types_on(s, define_indexed_types: false) }

          # As per https://www.apollographql.com/docs/federation/subgraph-spec/#resolve-requests-for-entities:
          #
          # > If no types are annotated with the key directive, then the `_Entity` union and `Query._entities`
          # > field should be removed from the schema.

          expect(schema_string).to exclude("_Entity")
          expect(type_def_from(schema_string, "Query")).to eq(<<~EOS.strip)
            type Query {
              _service: _Service!
            }
          EOS
        end

        it "avoids defining unneeded derived schema elements (filters, aggregations, query fields) for apollo types" do
          schema_state = nil

          schema_string = graphql_schema_string do |schema|
            schema_state = schema.state
            define_some_types_on(schema)
          end

          all_type_names = ::GraphQL::Schema.from_definition(schema_string).types.keys

          # Verify that the typical ElasticGraph derived types were not generated for the Apollo `FieldSet`/`_Entity` types.
          expect(all_type_names.grep(/FieldSet/)).to eq ["FieldSet"]
          expect(all_type_names.grep(/_Entity/)).to eq ["_Entity"]

          # Ensure `Query` doesn't have a typical ElasticGraph query field that it includes for all indexed types (including union indexed types)
          expect(type_def_from(schema_string, "Query")).to exclude("__entitys", "_EntityConnection")
        end

        it "has minimal impact on schema artifacts that are not used by the ElasticGraph GraphQL engine" do
          with_apollo_results = define_schema(with_apollo: true) { |s| define_some_types_on(s) }
          without_apollo_results = define_schema(with_apollo: false) { |s| define_some_types_on(s) }

          expect(with_apollo_results.datastore_scripts).to eq(without_apollo_results.datastore_scripts)
          expect(with_apollo_results.json_schemas_for(1)).to eq(without_apollo_results.json_schemas_for(1))
          expect(with_apollo_results.indices).to eq(without_apollo_results.indices)
          expect(with_apollo_results.index_templates).to eq(without_apollo_results.index_templates)

          with_apollo_runtime_metadata = SchemaArtifacts::RuntimeMetadata::Schema.from_hash(with_apollo_results.runtime_metadata.to_dumpable_hash)
          without_apollo_runtime_metadata = SchemaArtifacts::RuntimeMetadata::Schema.from_hash(without_apollo_results.runtime_metadata.to_dumpable_hash)
          expect(with_apollo_runtime_metadata.enum_types_by_name).to eq(without_apollo_runtime_metadata.enum_types_by_name)
          expect(with_apollo_runtime_metadata.object_types_by_name.except("_Entity", "_Service", "Query")).to eq(without_apollo_runtime_metadata.object_types_by_name.except("Query"))
        end

        it "records the apollo resolvers on the runtime metadata of the Query `_entities` and `_service` fields" do
          results = define_schema(with_apollo: true) { |s| define_some_types_on(s) }
          query_type = results.runtime_metadata.object_types_by_name.fetch("Query")

          expect(query_type.graphql_fields_by_name.fetch("_entities").resolver).to eq configured_graphql_resolver(:apollo_entities)
          expect(query_type.graphql_fields_by_name.fetch("_service").resolver).to eq configured_graphql_resolver(:apollo_service)
        end

        # We use `dont_validate_graphql_schema` here because the validation triggers the example exceptions we assert on from
        # the `derive_schema` call instead of happening when we expect them.
        it "has no problems with `_Entity` subtypes that have conflicting field definitions (even though a normal `union` type would not allow that)", :dont_validate_graphql_schema do
          define_types = lambda do |schema, define_manual_union_type:|
            schema.object_type "Component" do |t|
              t.field "id", "ID"
              t.field "number", "String"
              t.index "components"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID"
              t.field "number", "Int"
              t.index "widgets"
            end

            if define_manual_union_type
              schema.union_type "ComponentOrWidget" do |t|
                t.subtypes "Component", "Widget"
              end
            end
          end

          results = define_schema(with_apollo: false) do |schema|
            define_types.call(schema, define_manual_union_type: true)
          end

          # Demonstrate that this is usually a problem...
          expect { results.datastore_config }.to raise_error a_string_including("Conflicting definitions for field `number` on the subtypes of `ComponentOrWidget`.")
          expect { results.runtime_metadata }.to raise_error a_string_including("Conflicting definitions for field `number` on the subtypes of `ComponentOrWidget`.")

          results = define_schema(with_apollo: true) do |schema|
            define_types.call(schema, define_manual_union_type: false)
          end

          # ...but it's not a problem for the `_Entity` union type.
          results.runtime_metadata
          results.datastore_config

          # Demonstrate that the `_Entity` union type has `Component` and `Widget` as subtypes.
          expect(type_def_from(results.graphql_schema_string, "_Entity")).to eq "union _Entity = Component | Widget"
        end

        it "registers the GraphQL extension since the GraphQL endpoint will be buggy/broken if the extension is not loaded given the custom schema elements that have been added" do
          runtime_metadata = define_schema(with_apollo: true) { |s| define_some_types_on(s) }.runtime_metadata

          expect(runtime_metadata.graphql_extension_modules.map(&:extension_ref)).to include(
            SchemaArtifacts::RuntimeMetadata::Extension.new(GraphQL::EngineExtension, "elastic_graph/apollo/graphql/engine_extension", {}).to_dumpable_hash
          )
        end

        it "marks the built-in types (such as `PageInfo`) as being shareable since they are identically defined in every ElasticGraph schema and must be shareable to compose multiple ElasticGraph sub-graphs" do
          schema_string = graphql_schema_string do |schema|
            define_some_types_on(schema)

            schema.object_type "AnotherType" do |t|
              t.field "id", "ID!"
              t.paginated_collection_field "tags", "String"
              t.field "location", "GeoLocation"
              t.index "another_type"
            end
          end

          expect(type_def_from(schema_string, "PageInfo")).to start_with("type PageInfo @shareable {")
          expect(type_def_from(schema_string, "IntAggregatedValues")).to start_with("type IntAggregatedValues @shareable {")
          expect(type_def_from(schema_string, "StringConnection")).to start_with("type StringConnection @shareable {")
          expect(type_def_from(schema_string, "StringEdge")).to start_with("type StringEdge @shareable {")
          expect(type_def_from(schema_string, "GeoLocation")).to start_with("type GeoLocation @shareable {")

          # ...but `Query` must not be marked as shareable, since it's the root type and is not shared between sub-graphs.
          expect(type_def_from(schema_string, "Query")).to exclude("@shareable")
        end

        it "adds tags to built in types when no exceptions are given" do
          result = graphql_schema_string do |schema|
            schema.object_type "NotABuiltInType" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.index "widgets"
            end

            schema.tag_built_in_types_with("tag1")
            schema.tag_built_in_types_with("tag2")
          end

          all_type_names = ::GraphQL::Schema.from_definition(result).types.keys
          categorized_type_names = all_type_names.group_by do |type_name|
            if type_name.start_with?("__") || STOCK_GRAPHQL_SCALARS.include?(type_name)
              :not_explicitly_defined
            elsif type_name.include?("NotABuiltInType") ||
                type_name.start_with?("_", "link__", "federation__") ||
                %w[FieldSet].include?(type_name)
              :expect_no_tags
            else
              :expect_tags
            end
          end

          # Verify that we have types in all 3 categories as expected.
          expect(categorized_type_names).to include(:expect_no_tags, :expect_tags, :not_explicitly_defined)
          expect(categorized_type_names[:expect_no_tags]).not_to be_empty
          expect(categorized_type_names[:expect_tags]).not_to be_empty
          expect(categorized_type_names[:not_explicitly_defined]).not_to be_empty

          type_defs_by_name = all_type_names.to_h { |type| [type, type_def_from(result, type)] }
          expect(type_defs_by_name.select { |k, type_def| type_def.nil? }.keys).to match_array(categorized_type_names[:not_explicitly_defined])

          categorized_type_names[:expect_tags].each do |type|
            expect(type_defs_by_name[type]).to include("@tag(name: \"tag1\")")
            expect(type_defs_by_name[type]).to include("@tag(name: \"tag1\")", "@tag(name: \"tag2\")")
          end

          categorized_type_names[:expect_no_tags].each do |type|
            expect(type_defs_by_name[type]).not_to include("@tag")
          end
        end

        it "does not add tags to built in types when they are listed in `except: []`" do
          tag = "any-tag-name"
          schema_string = graphql_schema_string do |schema|
            define_some_types_on(schema)
            schema.tag_built_in_types_with(tag, except: ["IntAggregatedValues", "AggregatedIntValues"])
          end

          result = type_def_from(schema_string, "IntAggregatedValues")
          expect(result).to start_with("type IntAggregatedValues @shareable {")
          expect(result).to_not include("@tag")
        end

        it "adds its extension methods in a way that does not leak into a schema definition that lacks the apollo extension" do
          schema_extensions = [:tag_built_in_types_with]
          field_extensions = [:tag_with]

          graphql_schema_string(with_apollo: true) do |schema|
            expect(schema).to respond_to(*schema_extensions)

            schema.object_type "T1" do |t|
              t.field "id", "ID" do |f|
                expect(f).to respond_to(*field_extensions)
              end
            end

            schema.interface_type "T2" do |t|
              t.field "id", "ID" do |f|
                expect(f).to respond_to(*field_extensions)
              end
            end
          end

          graphql_schema_string(with_apollo: false) do |schema|
            expect(schema).not_to respond_to(*schema_extensions)

            schema.object_type "T1" do |t|
              t.field "id", "ID" do |f|
                expect(f).not_to respond_to(*field_extensions)
              end
              t.index "t1"
            end

            schema.interface_type "T2" do |t|
              t.field "id", "ID" do |f|
                expect(f).not_to respond_to(*field_extensions)
              end
            end
          end
        end

        describe "apollo entity reference support" do
          it "supports an entity reference field for a single id" do
            results = define_schema do |schema|
              schema.object_type "Component" do |t|
                t.field "the_id_field", "ID"
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "component_id", "ID!"
                # Demnonstrate that it works with and without a block, supporting both nullable and non-null fields.
                t.apollo_entity_ref_field "component1", "Component", id_field_name_in_index: "component_id"
                t.apollo_entity_ref_field "component2", "Component!", id_field_name_in_index: "component_id" do |f|
                  f.documentation "A component entity reference."
                end

                t.index "widgets"
              end
            end

            schema_string = results.graphql_schema_string
            expect(type_def_from(schema_string, "Widget", include_docs: true)).to eq(<<~EOS.strip)
              type Widget @key(fields: "id", resolvable: true) {
                id: ID
                component_id: ID!
                component1: Component
                """
                A component entity reference.
                """
                component2: Component!
              }
            EOS

            # The entity ref field should be available as a return field but not available for
            # filtering, grouping, aggregating, sorting, or highlighting.
            expect(type_def_from(schema_string, "WidgetFilterInput")).to eq(<<~EOS.strip)
              input WidgetFilterInput {
                #{schema_elements.any_of}: [WidgetFilterInput!]
                #{schema_elements.all_of}: [WidgetFilterInput!]
                #{schema_elements.not}: WidgetFilterInput
                id: IDFilterInput
                component_id: IDFilterInput
              }
            EOS
            expect(type_def_from(schema_string, "WidgetGroupedBy")).to eq(<<~EOS.strip)
              type WidgetGroupedBy {
                component_id: ID
              }
            EOS
            expect(type_def_from(schema_string, "WidgetAggregatedValues")).to eq(<<~EOS.strip)
              type WidgetAggregatedValues {
                id: NonNumericAggregatedValues
                component_id: NonNumericAggregatedValues
              }
            EOS
            expect(type_def_from(schema_string, "WidgetHighlights")).to eq(<<~EOS.strip)
              type WidgetHighlights {
                id: [String!]!
                component_id: [String!]!
              }
            EOS
            expect(type_def_from(schema_string, "WidgetSortOrderInput")).to eq(<<~EOS.strip)
              enum WidgetSortOrderInput {
                id_ASC
                id_DESC
                component_id_ASC
                component_id_DESC
              }
            EOS

            # The entity ref field should not be in the datastore index mapping.
            expect(
              results.datastore_config.dig("indices", "widgets", "mappings", "properties").keys.grep_v(/^__/)
            ).to contain_exactly("component_id", "id")

            runtime_graphql_fields_by_name = results
              .runtime_metadata
              .object_types_by_name
              .fetch("Widget")
              .graphql_fields_by_name

            # Verify the runtime metadata of the entity ref fields are correct.
            expect(runtime_graphql_fields_by_name.fetch("component1")).to eq(graphql_field_with(
              name_in_index: "component_id",
              resolver: configured_graphql_resolver(:apollo_entity_ref, source_id_field: "component_id", exposed_id_field: "the_id_field")
            ))
            expect(runtime_graphql_fields_by_name.fetch("component2")).to eq(graphql_field_with(
              name_in_index: "component_id",
              resolver: configured_graphql_resolver(:apollo_entity_ref, source_id_field: "component_id", exposed_id_field: "the_id_field")
            ))
          end

          it "supports an entity reference field for a list of ids" do
            results = define_schema do |schema|
              schema.object_type "Component" do |t|
                t.field "the_id_field", "ID"
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "component_ids", "[ID!]!", singular: "component_id"
                # Demnonstrate that it works with and without a block, supporting both nullable and non-null fields.
                t.apollo_entity_ref_field "components1", "[Component!]!", id_field_name_in_index: "component_ids"
                t.apollo_entity_ref_field "components2", "[Component]", id_field_name_in_index: "component_ids" do |f|
                  f.documentation "Component entity references."
                end

                t.index "widgets"
              end
            end

            schema_string = results.graphql_schema_string
            expect(type_def_from(schema_string, "Widget", include_docs: true)).to eq(<<~EOS.strip)
              type Widget @key(fields: "id", resolvable: true) {
                id: ID
                component_ids: [ID!]!
                components1: [Component!]!
                """
                Component entity references.
                """
                components2: [Component]
              }
            EOS

            # The entity ref field should be available as a return field but not available for
            # filtering, grouping, aggregating, sorting, or highlighting.
            expect(type_def_from(schema_string, "WidgetFilterInput")).to eq(<<~EOS.strip)
              input WidgetFilterInput {
                #{schema_elements.any_of}: [WidgetFilterInput!]
                #{schema_elements.all_of}: [WidgetFilterInput!]
                #{schema_elements.not}: WidgetFilterInput
                id: IDFilterInput
                component_ids: IDListFilterInput
              }
            EOS
            expect(type_def_from(schema_string, "WidgetGroupedBy")).to eq(<<~EOS.strip)
              type WidgetGroupedBy {
                component_id: ID
              }
            EOS
            expect(type_def_from(schema_string, "WidgetAggregatedValues")).to eq(<<~EOS.strip)
              type WidgetAggregatedValues {
                id: NonNumericAggregatedValues
                component_ids: NonNumericAggregatedValues
              }
            EOS
            expect(type_def_from(schema_string, "WidgetHighlights")).to eq(<<~EOS.strip)
              type WidgetHighlights {
                id: [String!]!
                component_ids: [String!]!
              }
            EOS
            expect(type_def_from(schema_string, "WidgetSortOrderInput")).to eq(<<~EOS.strip)
              enum WidgetSortOrderInput {
                id_ASC
                id_DESC
              }
            EOS

            # The entity ref field should not be in the datastore index mapping.
            expect(
              results.datastore_config.dig("indices", "widgets", "mappings", "properties").keys.grep_v(/^__/)
            ).to contain_exactly("component_ids", "id")

            runtime_graphql_fields_by_name = results
              .runtime_metadata
              .object_types_by_name
              .fetch("Widget")
              .graphql_fields_by_name

            # Verify the runtime metadata of the entity ref fields are correct.
            expect(runtime_graphql_fields_by_name.fetch("components1")).to eq(graphql_field_with(
              name_in_index: "component_ids",
              resolver: configured_graphql_resolver(:apollo_entity_ref_list, source_ids_field: "component_ids", exposed_id_field: "the_id_field")
            ))
            expect(runtime_graphql_fields_by_name.fetch("components2")).to eq(graphql_field_with(
              name_in_index: "component_ids",
              resolver: configured_graphql_resolver(:apollo_entity_ref_list, source_ids_field: "component_ids", exposed_id_field: "the_id_field")
            ))
          end

          it "supports a paginated entity reference collection field backed by a non-paginated list field" do
            results = define_schema do |schema|
              schema.object_type "Component" do |t|
                t.field "the_id_field", "ID"
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "component_ids", "[ID!]!", singular: "component_id"
                # Demnonstrate that it works with and without a block
                t.apollo_entity_ref_paginated_collection_field "components1", "Component", id_field_name_in_index: "component_ids"
                t.apollo_entity_ref_paginated_collection_field "components2", "Component", id_field_name_in_index: "component_ids" do |f|
                  f.directive "deprecated"
                end

                t.index "widgets"
              end
            end

            schema_string = results.graphql_schema_string
            expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
              type Widget @key(fields: "id", resolvable: true) {
                id: ID
                component_ids: [ID!]!
                components1(
                  first: Int
                  after: Cursor
                  last: Int
                  before: Cursor): ComponentConnection
                components2(
                  first: Int
                  after: Cursor
                  last: Int
                  before: Cursor): ComponentConnection @deprecated
              }
            EOS

            # The entity ref field should be available as a return field but not available for
            # filtering, grouping, aggregating, sorting, or highlighting.
            expect(type_def_from(schema_string, "WidgetFilterInput")).to eq(<<~EOS.strip)
              input WidgetFilterInput {
                #{schema_elements.any_of}: [WidgetFilterInput!]
                #{schema_elements.all_of}: [WidgetFilterInput!]
                #{schema_elements.not}: WidgetFilterInput
                id: IDFilterInput
                component_ids: IDListFilterInput
              }
            EOS
            expect(type_def_from(schema_string, "WidgetGroupedBy")).to eq(<<~EOS.strip)
              type WidgetGroupedBy {
                component_id: ID
              }
            EOS
            expect(type_def_from(schema_string, "WidgetAggregatedValues")).to eq(<<~EOS.strip)
              type WidgetAggregatedValues {
                id: NonNumericAggregatedValues
                component_ids: NonNumericAggregatedValues
              }
            EOS
            expect(type_def_from(schema_string, "WidgetHighlights")).to eq(<<~EOS.strip)
              type WidgetHighlights {
                id: [String!]!
                component_ids: [String!]!
              }
            EOS
            expect(type_def_from(schema_string, "WidgetSortOrderInput")).to eq(<<~EOS.strip)
              enum WidgetSortOrderInput {
                id_ASC
                id_DESC
              }
            EOS

            # The entity ref field should not be in the datastore index mapping.
            expect(
              results.datastore_config.dig("indices", "widgets", "mappings", "properties").keys.grep_v(/^__/)
            ).to contain_exactly("component_ids", "id")

            runtime_graphql_fields_by_name = results
              .runtime_metadata
              .object_types_by_name
              .fetch("Widget")
              .graphql_fields_by_name

            # Verify the runtime metadata of the entity ref fields are correct.
            expect(runtime_graphql_fields_by_name.fetch("components1")).to eq(graphql_field_with(
              name_in_index: "component_ids",
              resolver: configured_graphql_resolver(:apollo_entity_ref_paginated, source_ids_field: "component_ids", exposed_id_field: "the_id_field")
            ))
            expect(runtime_graphql_fields_by_name.fetch("components2")).to eq(graphql_field_with(
              name_in_index: "component_ids",
              resolver: configured_graphql_resolver(:apollo_entity_ref_paginated, source_ids_field: "component_ids", exposed_id_field: "the_id_field")
            ))
          end

          it "supports a paginated entity reference collection field backed by a paginated list field" do
            results = define_schema do |schema|
              schema.object_type "Component" do |t|
                t.field "the_id_field", "ID"
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.paginated_collection_field "component_ids", "ID", singular: "component_id"
                # Demnonstrate that it works with and without a block
                t.apollo_entity_ref_paginated_collection_field "components1", "Component", id_field_name_in_index: "component_ids"
                t.apollo_entity_ref_paginated_collection_field "components2", "Component", id_field_name_in_index: "component_ids" do |f|
                  f.directive "deprecated"
                end

                t.index "widgets"
              end
            end

            schema_string = results.graphql_schema_string
            expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
              type Widget @key(fields: "id", resolvable: true) {
                id: ID
                component_ids(
                  first: Int
                  after: Cursor
                  last: Int
                  before: Cursor): IDConnection
                components1(
                  first: Int
                  after: Cursor
                  last: Int
                  before: Cursor): ComponentConnection
                components2(
                  first: Int
                  after: Cursor
                  last: Int
                  before: Cursor): ComponentConnection @deprecated
              }
            EOS

            # The entity ref field should be available as a return field but not available for
            # filtering, grouping, aggregating, sorting, or highlighting.
            expect(type_def_from(schema_string, "WidgetFilterInput")).to eq(<<~EOS.strip)
              input WidgetFilterInput {
                #{schema_elements.any_of}: [WidgetFilterInput!]
                #{schema_elements.all_of}: [WidgetFilterInput!]
                #{schema_elements.not}: WidgetFilterInput
                id: IDFilterInput
                component_ids: IDListFilterInput
              }
            EOS
            expect(type_def_from(schema_string, "WidgetGroupedBy")).to eq(<<~EOS.strip)
              type WidgetGroupedBy {
                component_id: ID
              }
            EOS
            expect(type_def_from(schema_string, "WidgetAggregatedValues")).to eq(<<~EOS.strip)
              type WidgetAggregatedValues {
                id: NonNumericAggregatedValues
                component_ids: NonNumericAggregatedValues
              }
            EOS
            expect(type_def_from(schema_string, "WidgetHighlights")).to eq(<<~EOS.strip)
              type WidgetHighlights {
                id: [String!]!
                component_ids: [String!]!
              }
            EOS
            expect(type_def_from(schema_string, "WidgetSortOrderInput")).to eq(<<~EOS.strip)
              enum WidgetSortOrderInput {
                id_ASC
                id_DESC
              }
            EOS

            # The entity ref field should not be in the datastore index mapping.
            expect(
              results.datastore_config.dig("indices", "widgets", "mappings", "properties").keys.grep_v(/^__/)
            ).to contain_exactly("component_ids", "id")

            runtime_graphql_fields_by_name = results
              .runtime_metadata
              .object_types_by_name
              .fetch("Widget")
              .graphql_fields_by_name

            # Verify the runtime metadata of the entity ref fields are correct.
            expect(runtime_graphql_fields_by_name.fetch("components1")).to eq(graphql_field_with(
              name_in_index: "component_ids",
              resolver: configured_graphql_resolver(:apollo_entity_ref_paginated, source_ids_field: "component_ids", exposed_id_field: "the_id_field")
            ))
            expect(runtime_graphql_fields_by_name.fetch("components2")).to eq(graphql_field_with(
              name_in_index: "component_ids",
              resolver: configured_graphql_resolver(:apollo_entity_ref_paginated, source_ids_field: "component_ids", exposed_id_field: "the_id_field")
            ))
          end

          it "validates that the entity ref type is an object type" do
            expect {
              define_schema do |schema|
                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "component_id", "ID"
                  t.apollo_entity_ref_field "component", "String", id_field_name_in_index: "component_id"
                  t.index "widgets"
                end
              end
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Widget.component` is invalid: the referenced type (`String`) " \
              "is not an object type as required by `apollo_entity_ref_field`."
            )
          end

          it "validates that the entity ref type has only one field as the custom resolver is not capable of returning any other fields" do
            expect {
              define_schema do |schema|
                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "component_id", "ID"
                  t.apollo_entity_ref_field "component", "Component", id_field_name_in_index: "component_id"
                  t.index "widgets"
                end

                schema.object_type "Component" do |t|
                  t.field "id", "ID"
                  t.field "name", "String"
                end
              end
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Widget.component` is invalid: `apollo_entity_ref_field` can only be used for " \
              "types with a single field, but `Component` has 2 fields."
            )
          end

          it "validates that the entity ref type's single field is an `ID` field" do
            define_schema_with_entity_ref_field_of_type = lambda do |entity_ref_field_type|
              define_schema do |schema|
                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "component_id", "ID"
                  t.apollo_entity_ref_field "component", "Component", id_field_name_in_index: "component_id"
                  t.index "widgets"
                end

                schema.object_type "Component" do |t|
                  t.field "id", entity_ref_field_type
                end
              end
            end

            expect {
              define_schema_with_entity_ref_field_of_type.call("String")
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Widget.component` is invalid: `apollo_entity_ref_field` can only be used for " \
              "types with a single `ID` field, but the type of `Component.id` is `String`."
            )

            expect {
              define_schema_with_entity_ref_field_of_type.call("[ID!]!")
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Widget.component` is invalid: `apollo_entity_ref_field` can only be used for " \
              "types with a single `ID` field, but the type of `Component.id` is `[ID!]!`."
            )

            expect {
              define_schema_with_entity_ref_field_of_type.call("ID")
            }.not_to raise_error

            expect {
              define_schema_with_entity_ref_field_of_type.call("ID!")
            }.not_to raise_error
          end

          it "validates that the field referenced from `id_field_name_in_index` exists" do
            expect {
              define_schema do |schema|
                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "component_id", "ID"
                  t.apollo_entity_ref_field "component", "Component", id_field_name_in_index: "component_id2"
                  t.index "widgets"
                end

                schema.object_type "Component" do |t|
                  t.field "id", "ID"
                end
              end
            }.to raise_error Errors::SchemaError, a_string_including(
              "GraphQL-only field `Widget.component` has a `name_in_index` (component_id2) which does not reference an existing indexing field."
            )
          end

          it "validates that the field referenced from `id_field_name_in_index` is an `ID` field" do
            expect {
              define_schema do |schema|
                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "component_id", "String"
                  t.apollo_entity_ref_field "component", "Component", id_field_name_in_index: "component_id"
                  t.index "widgets"
                end

                schema.object_type "Component" do |t|
                  t.field "id", "ID"
                end
              end
            }.to raise_error Errors::SchemaError, a_string_including(
              "`id_field_name_in_index` must reference an `ID` field, but the type of `component_id` is `String`."
            )
          end

          it "validates that the field referenced from `id_field_name_in_index` for a paginated field is an `ID` collection field" do
            expect {
              define_schema do |schema|
                schema.object_type "Widget" do |t|
                  t.field "id", "ID"
                  t.field "component_id", "ID"
                  t.apollo_entity_ref_paginated_collection_field "component", "Component", id_field_name_in_index: "component_id"
                  t.index "widgets"
                end

                schema.object_type "Component" do |t|
                  t.field "id", "ID"
                end
              end
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Widget.component` is invalid: `id_field_name_in_index` must reference an id collection field, " \
              "but the type of `component_id` is `ID`."
            )
          end
        end

        it "provides an API on `object_type` and `interface_type` to make it easy to tag a field and all derived schema elements for inclusion in an apollo contract variant" do
          schema_string = graphql_schema_string do |schema|
            # For full branch test coverage, verify that these overridden methods still work when no block is given.
            schema.object_type "EmptyObject"

            schema.object_type "WidgetOptions" do |t|
              t.field "color", "String" do |f|
                f.tag_with "public"
              end

              t.field "size", "Int"
            end

            schema.interface_type "Identifiable" do |t|
              t.field "id", "ID!", groupable: false
              t.field "token", "String" do |f|
                f.tag_with "public-interface"
              end
            end

            schema.object_type "Widget" do |t|
              t.implements "Identifiable"

              t.field "id", "ID!", groupable: false

              t.field "token", "String"

              t.field "options1", "WidgetOptions" do |f|
                f.tag_with "public"
              end

              t.field "options2", "WidgetOptions" do |f|
                f.tag_with "internal"
              end

              t.field "name", "String" do |f|
                f.tag_with "public"
              end

              # Verify we can use it on `relates_to_*` fields as well (originally this didn't work!)
              t.relates_to_one "parent_widget", "Widget", via: "parent_id", dir: :out do |f|
                f.tag_with "public"
              end

              t.index "widgets"
            end
          end

          considered_types = []

          expect_widget_type_tagging_of_name_and_option1_color do |type_name|
            considered_types << type_name
            type_def_from(schema_string, type_name)
          end

          expect_identifiable_type_tagging_of_token do |type_name|
            considered_types << type_name
            type_def_from(schema_string, type_name)
          end

          all_types = ::GraphQL::Schema.from_definition(schema_string).types.keys
          widget_type_names = all_types.grep(/Widget/)
          identifiable_type_names = all_types.grep(/Identifiable/)

          # Here we are verifying that we properly verified all related types. If a new ElasticGraph feature causes new types
          # to be generated for the `Widget` and `Identifiable` source types, we will want this test to be updated to cover them.
          # This expectation should fail, notifying us of the need to cover the new type.
          expect(widget_type_names + identifiable_type_names).to match_array(
            considered_types + [
              # We do not look at these types because the fields on them are based on the relay spec and not based on
              # the fields of the Widget/Identifiable source types.
              "WidgetConnection", "WidgetEdge", "WidgetAggregationConnection", "WidgetAggregationEdge",
              "IdentifiableConnection", "IdentifiableEdge", "IdentifiableAggregationConnection", "IdentifiableAggregationEdge"
            ] + [
              # We do not look at these types because the fields on them are static (`groupedBy`/`count`/`aggregatedValues`) and
              # are not derived fields from the Widget/Identifiable source types.
              "WidgetAggregation", "IdentifiableAggregation"
            ]
          )
        end

        def expect_widget_type_tagging_of_name_and_option1_color(&type_def_for)
          expect(type_def_for.call("Widget")).to eq(<<~EOS.strip)
            type Widget implements Identifiable @key(fields: "id") {
              id: ID!
              name: String @tag(name: "public")
              options1: WidgetOptions @tag(name: "public")
              options2: WidgetOptions @tag(name: "internal")
              parent_widget: Widget @tag(name: "public")
              token: String
            }
          EOS

          expect(type_def_for.call("WidgetFilterInput")).to eq(<<~EOS.strip)
            input WidgetFilterInput {
              #{schema_elements.all_of}: [WidgetFilterInput!]
              #{schema_elements.any_of}: [WidgetFilterInput!]
              id: IDFilterInput
              name: StringFilterInput @tag(name: "public")
              not: WidgetFilterInput
              options1: WidgetOptionsFilterInput @tag(name: "public")
              options2: WidgetOptionsFilterInput @tag(name: "internal")
              token: StringFilterInput
            }
          EOS

          expect(type_def_for.call("WidgetGroupedBy")).to eq(<<~EOS.strip)
            type WidgetGroupedBy {
              name: String @tag(name: "public")
              options1: WidgetOptionsGroupedBy @tag(name: "public")
              options2: WidgetOptionsGroupedBy @tag(name: "internal")
              token: String
            }
          EOS

          expect(type_def_for.call("WidgetHighlights")).to eq(<<~EOS.strip)
            type WidgetHighlights {
              id: [String!]!
              name: [String!]! @tag(name: "public")
              options1: WidgetOptionsHighlights @tag(name: "public")
              options2: WidgetOptionsHighlights @tag(name: "internal")
              token: [String!]!
            }
          EOS

          expect(type_def_for.call("WidgetAggregatedValues")).to eq(<<~EOS.strip)
            type WidgetAggregatedValues {
              id: NonNumericAggregatedValues
              name: NonNumericAggregatedValues @tag(name: "public")
              options1: WidgetOptionsAggregatedValues @tag(name: "public")
              options2: WidgetOptionsAggregatedValues @tag(name: "internal")
              token: NonNumericAggregatedValues
            }
          EOS

          expect(type_def_for.call("WidgetOptions")).to eq(<<~EOS.strip)
            type WidgetOptions {
              color: String @tag(name: "public")
              size: Int
            }
          EOS

          expect(type_def_for.call("WidgetOptionsFilterInput")).to eq(<<~EOS.strip)
            input WidgetOptionsFilterInput {
              #{schema_elements.all_of}: [WidgetOptionsFilterInput!]
              #{schema_elements.any_of}: [WidgetOptionsFilterInput!]
              color: StringFilterInput @tag(name: "public")
              not: WidgetOptionsFilterInput
              size: IntFilterInput
            }
          EOS

          expect(type_def_for.call("WidgetOptionsGroupedBy")).to eq(<<~EOS.strip)
            type WidgetOptionsGroupedBy {
              color: String @tag(name: "public")
              size: Int
            }
          EOS

          expect(type_def_for.call("WidgetOptionsHighlights")).to eq(<<~EOS.strip)
            type WidgetOptionsHighlights {
              color: [String!]! @tag(name: "public")
            }
          EOS

          expect(type_def_for.call("WidgetOptionsAggregatedValues")).to eq(<<~EOS.strip)
            type WidgetOptionsAggregatedValues {
              color: NonNumericAggregatedValues @tag(name: "public")
              size: IntAggregatedValues
            }
          EOS

          expect(type_def_for.call("WidgetSortOrderInput")).to eq(<<~EOS.strip)
            enum WidgetSortOrderInput {
              id_ASC
              id_DESC
              name_ASC @tag(name: "public")
              name_DESC @tag(name: "public")
              options1_color_ASC @tag(name: "public")
              options1_color_DESC @tag(name: "public")
              options1_size_ASC
              options1_size_DESC
              options2_color_ASC
              options2_color_DESC
              options2_size_ASC
              options2_size_DESC
              token_ASC
              token_DESC
            }
          EOS
        end

        def expect_identifiable_type_tagging_of_token(&type_def_for)
          expect(type_def_for.call("Identifiable")).to eq(<<~EOS.strip)
            interface Identifiable {
              id: ID!
              token: String @tag(name: "public-interface")
            }
          EOS

          # For these 3 types, the generated types uses the union of fields of all subtypes, and automatically inherits
          # the tagging of those source fields. That's why `name`, `options1`, etc are tagged with `public` below.
          expect(type_def_for.call("IdentifiableFilterInput")).to eq(<<~EOS.strip)
            input IdentifiableFilterInput {
              #{schema_elements.all_of}: [IdentifiableFilterInput!]
              #{schema_elements.any_of}: [IdentifiableFilterInput!]
              id: IDFilterInput
              name: StringFilterInput @tag(name: "public")
              not: IdentifiableFilterInput
              options1: WidgetOptionsFilterInput @tag(name: "public")
              options2: WidgetOptionsFilterInput @tag(name: "internal")
              token: StringFilterInput @tag(name: "public-interface")
            }
          EOS

          expect(type_def_for.call("IdentifiableGroupedBy")).to eq(<<~EOS.strip)
            type IdentifiableGroupedBy {
              name: String @tag(name: "public")
              options1: WidgetOptionsGroupedBy @tag(name: "public")
              options2: WidgetOptionsGroupedBy @tag(name: "internal")
              token: String @tag(name: "public-interface")
            }
          EOS

          expect(type_def_for.call("IdentifiableHighlights")).to eq(<<~EOS.strip)
            type IdentifiableHighlights {
              id: [String!]!
              name: [String!]! @tag(name: "public")
              options1: WidgetOptionsHighlights @tag(name: "public")
              options2: WidgetOptionsHighlights @tag(name: "internal")
              token: [String!]! @tag(name: "public-interface")
            }
          EOS

          expect(type_def_for.call("IdentifiableAggregatedValues")).to eq(<<~EOS.strip)
            type IdentifiableAggregatedValues {
              id: NonNumericAggregatedValues
              name: NonNumericAggregatedValues @tag(name: "public")
              options1: WidgetOptionsAggregatedValues @tag(name: "public")
              options2: WidgetOptionsAggregatedValues @tag(name: "internal")
              token: NonNumericAggregatedValues @tag(name: "public-interface")
            }
          EOS

          expect(type_def_for.call("IdentifiableSortOrderInput")).to eq(<<~EOS.strip)
            enum IdentifiableSortOrderInput {
              id_ASC
              id_DESC
              name_ASC @tag(name: "public")
              name_DESC @tag(name: "public")
              options1_color_ASC @tag(name: "public")
              options1_color_DESC @tag(name: "public")
              options1_size_ASC
              options1_size_DESC
              options2_color_ASC
              options2_color_DESC
              options2_size_ASC
              options2_size_DESC
              token_ASC @tag(name: "public-interface")
              token_DESC @tag(name: "public-interface")
            }
          EOS
        end

        def define_schema(with_apollo: true, &block)
          extension_modules = with_apollo ? [SchemaDefinition::APIExtension] : []
          super(schema_element_name_form: schema_element_name_form, extension_modules: extension_modules, &block)
        end
      end

      def graphql_schema_string(with_apollo: true, &block)
        schema_string = define_schema(with_apollo: with_apollo, &block).graphql_schema_string
        ::GraphQL::Schema.from_definition(schema_string).to_definition.strip
      end

      def define_some_types_on(schema, define_indexed_types: true, id_is_indexing_only: [])
        schema.object_type "IndexedType1" do |t|
          t.field "embedded", "EmbeddedObjectType1"
          t.field "graphql", "String", name_in_index: "index"
          t.field "id", "ID!", indexing_only: id_is_indexing_only.include?("IndexedType1")
          t.field "num", "Int"
          t.index "index1" if define_indexed_types
        end

        schema.object_type "IndexedType2" do |t|
          t.field "id", "ID!", indexing_only: id_is_indexing_only.include?("IndexedType2")

          # Ensure there's at least one field defined on the GraphQL type--if `id` is indexing-only, we need another field defined.
          t.field "name", "String" if id_is_indexing_only.include?("IndexedType2")
          t.index "index1" if define_indexed_types
        end

        schema.object_type "EmbeddedObjectType1" do |t|
          t.field "id", "ID!"
        end
      end

      def define_unindexed_types
        graphql_schema_string do |schema|
          %w[UnindexedType1 UnindexedType2].each do |type|
            schema.object_type type do |t|
              t.field "id", "ID!"
              t.field "key", "KeyType1!"
              t.field "field1", "String"
              t.field "field2", "String"
              t.field "field3", "String" do |f|
                f.apollo_external
              end

              yield t
            end
          end

          schema.object_type "KeyType1" do |t|
            t.field "keyType", "KeyType2"
          end
          schema.object_type "KeyType2" do |t|
            t.field "field1", "ID!"
          end
        end
      end
    end
  end
end
