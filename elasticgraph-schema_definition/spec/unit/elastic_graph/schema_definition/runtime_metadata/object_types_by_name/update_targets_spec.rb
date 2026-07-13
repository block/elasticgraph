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
    RSpec.describe "RuntimeMetadata #object_types_by_name #update_targets" do
      include_context "object type metadata support"

      context "when `sourced_from` is used" do
        it "dumps an update target on the related type, regardless of the definition order of the relation compared to the `sourced_from` fields" do
          update_targets_relation_before_fields = update_targets_for("WidgetWorkspace") do |t|
            t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

            t.field "workspace_name", "String" do |f|
              f.sourced_from "workspace", "name"
            end

            t.field "workspace_created_at", "DateTime" do |f|
              f.sourced_from "workspace", "created_at"
            end
          end

          update_targets_fields_before_relation = update_targets_for("WidgetWorkspace") do |t|
            t.field "workspace_name", "String" do |f|
              f.sourced_from "workspace", "name"
            end

            t.field "workspace_created_at", "DateTime" do |f|
              f.sourced_from "workspace", "created_at"
            end

            t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in
          end

          expect(update_targets_relation_before_fields).to eq(update_targets_fields_before_relation)
          expect_widget_update_target_with(
            update_targets_relation_before_fields,
            id_source: "widget_ids",
            routing_value_source: nil,
            relationship: "workspace",
            top_level_fields_params: {
              "workspace_name" => dynamic_param_with(source_path: "name", cardinality: :one),
              "workspace_created_at" => dynamic_param_with(source_path: "created_at", cardinality: :one)
            }
          )
        end

        it "dumps an update target for an `indexing_only: true` relationship used with `sourced_from`" do
          update_targets = update_targets_for("WidgetWorkspace") do |t|
            t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in, indexing_only: true

            t.field "workspace_name", "String" do |f|
              f.sourced_from "workspace", "name"
            end
          end

          expect_widget_update_target_with(
            update_targets,
            id_source: "widget_ids",
            routing_value_source: nil,
            relationship: "workspace",
            top_level_fields_params: {
              "workspace_name" => dynamic_param_with(source_path: "name", cardinality: :one)
            }
          )
        end

        it "excludes the `sourced_from` fields from the `params` of the main type since we don't want updates of that type stomping a value indexed from an alternate source" do
          update_targets = update_targets_for("Widget")

          expect_widget_update_target_with(
            update_targets,
            id_source: "id",
            routing_value_source: "id",
            relationship: SELF_RELATIONSHIP_NAME,
            top_level_fields_params: {
              # Importantly, `workspace_name` and `workspace_created_at` are NOT in this map.
              "name" => dynamic_param_with(source_path: "name", cardinality: :one)
            }
          )
        end

        it "allows an alternate `name_in_index` to be used on the referenced field" do
          update_targets = update_targets_for("WidgetWorkspace", widget_workspace_name_opts: {name_in_index: "name2"}) do |t|
            t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

            t.field "workspace_name", "String" do |f|
              f.sourced_from "workspace", "name"
            end
          end

          expect_widget_update_target_with(
            update_targets,
            id_source: "widget_ids",
            routing_value_source: nil,
            relationship: "workspace",
            top_level_fields_params: {
              "workspace_name" => dynamic_param_with(source_path: "name2", cardinality: :one)
            }
          )
        end

        it "allows an alternate `name_in_index` to be used on the local field" do
          update_targets = update_targets_for("WidgetWorkspace") do |t|
            t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

            t.field "workspace_name", "String", name_in_index: "workspace_name2" do |f|
              f.sourced_from "workspace", "name"
            end
          end

          expect_widget_update_target_with(
            update_targets,
            id_source: "widget_ids",
            routing_value_source: nil,
            relationship: "workspace",
            top_level_fields_params: {
              "workspace_name2" => dynamic_param_with(source_path: "name", cardinality: :one)
            }
          )
        end

        it "allows the field to be sourced from a nested field" do
          update_targets = update_targets_for("WidgetWorkspace") do |t|
            t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

            t.field "workspace_name", "String" do |f|
              f.sourced_from "workspace", "nested.further_nested.name"
            end
          end

          expect_widget_update_target_with(
            update_targets,
            id_source: "widget_ids",
            routing_value_source: nil,
            relationship: "workspace",
            top_level_fields_params: {
              "workspace_name" => dynamic_param_with(source_path: "nested.further_nested_in_index.name", cardinality: :one)
            }
          )
        end

        it "allows non-nullability on the parent parts of a nested field" do
          update_targets = update_targets_for("WidgetWorkspace", widget_workspace_nested_1_further_nested: "WidgetWorkspaceNested2!") do |t|
            t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

            t.field "workspace_name", "String" do |f|
              f.sourced_from "workspace", "nested.further_nested.name"
            end
          end

          expect_widget_update_target_with(
            update_targets,
            id_source: "widget_ids",
            routing_value_source: nil,
            relationship: "workspace",
            top_level_fields_params: {
              "workspace_name" => dynamic_param_with(source_path: "nested.further_nested_in_index.name", cardinality: :one)
            }
          )
        end

        it "does not dump any update targets for interface types with no defined index, even if they are implemented by other types with defined indices" do
          metadata = object_type_metadata_for "WidgetWorkspace" do |s|
            s.interface_type "NamedEntity" do |t|
              t.field "name", "String"
            end

            s.object_type "Widget" do |t|
              t.implements "NamedEntity"
              t.field "id", "ID!"
              t.field "name", "String"
              t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

              t.field "workspace_name", "String" do |f|
                f.sourced_from "workspace", "name"
              end

              t.index "widgets" do |i|
                i.has_had_multiple_sources!
              end
            end

            s.object_type "WidgetWorkspace" do |t|
              t.implements "NamedEntity"
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "widget_ids", "[ID!]!"
              t.index "widget_workspaces"
            end
          end

          expect(metadata.update_targets.map(&:type)).to exclude "NamedEntity"
        end

        context "on a type that uses custom routing" do
          it "determines the `routing_value_source` from an `equivalent_field` configured on the relation" do
            source = routing_value_source_for_widget_update_target_of("WidgetWorkspace") do |t|
              expect(t.name).to eq "Widget"

              t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                # Including multiple `equivalent_field` calls to force it to use the right one.
                r.equivalent_field "id", locally_named: "id"
                r.equivalent_field "workspace_owner_id", locally_named: "owner_id"
                r.equivalent_field "name", locally_named: "name"
              end
            end

            expect(source).to eq "workspace_owner_id"
          end

          it "allows `locally_named:` to be omitted when defining equivalent fields, defaulting the local name to the same as the remote name" do
            source = routing_value_source_for_widget_update_target_of("WidgetWorkspace", on_widget_workspace_type: ->(t) { t.field "owner_id", "ID!" }) do |t|
              expect(t.name).to eq "Widget"

              t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                r.equivalent_field "owner_id"
              end
            end

            expect(source).to eq "owner_id"
          end

          it "raises a clear error if an `equivalent_field` is not defined for the custom routing field" do
            expect {
              routing_value_source_for_widget_update_target_of("WidgetWorkspace") do |t|
                expect(t.name).to eq "Widget"

                t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                  r.equivalent_field "another_id"
                end
              end
            }.to raise_error Errors::SchemaError, a_string_including(
              "Cannot update `Widget` documents",
              "related `workspace` events",
              "`Widget` uses custom shard routing",
              "don't know what `workspace` field to use",
              "`Widget` update requests",
              "`Widget.workspace` relationship definition",
              '`rel.equivalent_field "[WidgetWorkspace field]", locally_named: "owner_id"`'
            )
          end

          it "resolves the custom routing field using the public GraphQL field name instead of the internal `name_in_index`" do
            source = routing_value_source_for_widget_update_target_of("WidgetWorkspace", owner_id_field_opts: {name_in_index: "owner_id_in_index"}) do |t|
              expect(t.name).to eq "Widget"

              t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                r.equivalent_field "workspace_owner_id", locally_named: "owner_id"
              end
            end

            expect(source).to eq "workspace_owner_id"
          end

          it "records the `name_in_index` as the `routing_value_source` since the `elasticgraph-indexer` logic that uses it expects the index field name" do
            source = routing_value_source_for_widget_update_target_of("WidgetWorkspace", on_widget_workspace_type: ->(t) { t.field "woid", "ID!", name_in_index: "widget_order_id" }) do |t|
              expect(t.name).to eq "Widget"

              t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                r.equivalent_field "woid", locally_named: "owner_id"
              end
            end

            expect(source).to eq "widget_order_id"
          end

          it "allows the `routing_value_source` to be an indexing-only field, but does not allow it to be a graphql-only field" do
            source = routing_value_source_for_widget_update_target_of("WidgetWorkspace", on_widget_workspace_type: ->(t) { t.field "owner_id", "ID!", indexing_only: true }) do |t|
              expect(t.name).to eq "Widget"

              t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                r.equivalent_field "owner_id"
              end
            end

            expect(source).to eq "owner_id"

            expect {
              routing_value_source_for_widget_update_target_of("WidgetWorkspace", on_widget_workspace_type: ->(t) { t.field "owner_id", "ID", graphql_only: true }) do |t|
                expect(t.name).to eq "Widget"

                t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                  r.equivalent_field "owner_id"
                end
              end
            }.to raise_error Errors::SchemaError, a_string_including("`WidgetWorkspace.owner_id` (referenced from an `equivalent_field` defined on `Widget.workspace`) does not exist")
          end

          it "supports nested fields as a `routing_value_source`" do
            source = routing_value_source_for_widget_update_target_of("WidgetWorkspace") do |t|
              expect(t.name).to eq "Widget"

              t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                r.equivalent_field "nested.owner_id", locally_named: "owner_id"
              end
            end

            expect(source).to eq "nested.owner_id"
          end

          def routing_value_source_for_widget_update_target_of(type, owner_id_field_opts: {}, **options)
            update_targets = update_targets_for(type, on_widgets_index: ->(index) { index.route_with "owner_id" }, **options) do |t|
              t.field "owner_id", "ID!", **owner_id_field_opts

              t.field "workspace_name", "String" do |f|
                f.sourced_from "workspace", "name"
              end

              yield t
            end

            expect(update_targets.count { |t| t.type == "Widget" }).to eq(1)
            widget_target = update_targets.find { |t| t.type == "Widget" }
            widget_target.routing_value_source
          end
        end

        context "on a type that uses a rollover index" do
          it "determines the `rollover_timestamp_value_source` from an `equivalent_field` configured on the relation" do
            source = rollover_timestamp_value_source_for_widget_update_target_of("WidgetWorkspace") do |t|
              expect(t.name).to eq "Widget"

              t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                # Including multiple `equivalent_field` calls to force it to use the right one.
                r.equivalent_field "workspace_owner_id", locally_named: "id"
                r.equivalent_field "workspace_created_at", locally_named: "created_at"
                r.equivalent_field "name", locally_named: "name"
              end
            end

            expect(source).to eq "workspace_created_at"
          end

          it "allows `locally_named:` to be omitted when defining equivalent fields, defaulting the local name to the same as the remote name" do
            source = rollover_timestamp_value_source_for_widget_update_target_of("WidgetWorkspace") do |t|
              expect(t.name).to eq "Widget"

              t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                r.equivalent_field "created_at"
              end
            end

            expect(source).to eq "created_at"
          end

          it "raises a clear error if an `equivalent_field` is not defined for the custom routing field" do
            expect {
              rollover_timestamp_value_source_for_widget_update_target_of("WidgetWorkspace") do |t|
                expect(t.name).to eq "Widget"

                t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                  r.equivalent_field "another_timestamp_field"
                end
              end
            }.to raise_error Errors::SchemaError, a_string_including(
              "Cannot update `Widget` documents",
              "related `workspace` events",
              "`Widget` uses a rollover index",
              "don't know what `workspace` timestamp field to use",
              "`Widget` update requests",
              "`Widget.workspace` relationship definition",
              '`rel.equivalent_field "[WidgetWorkspace field]", locally_named: "created_at"`'
            )
          end

          it "resolves the custom routing field using the public GraphQL field name instead of the internal `name_in_index`" do
            source = rollover_timestamp_value_source_for_widget_update_target_of("WidgetWorkspace", created_at_field_opts: {name_in_index: "created_at_in_index"}) do |t|
              expect(t.name).to eq "Widget"

              t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                r.equivalent_field "workspace_created_at", locally_named: "created_at"
              end
            end

            expect(source).to eq "workspace_created_at"
          end

          it "records the `name_in_index` as the `routing_value_source` since the `elasticgraph-indexer` logic that uses it expects the index field name" do
            source = rollover_timestamp_value_source_for_widget_update_target_of("WidgetWorkspace", on_widget_workspace_type: ->(t) { t.field "w_created_at", "DateTime", name_in_index: "widget_created_at" }) do |t|
              expect(t.name).to eq "Widget"

              t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                r.equivalent_field "w_created_at", locally_named: "created_at"
              end
            end

            expect(source).to eq "widget_created_at"
          end

          it "allows the `routing_value_source` to be an indexing-only field, but does not allow it to be a graphql-only field" do
            source = rollover_timestamp_value_source_for_widget_update_target_of("WidgetWorkspace", on_widget_workspace_type: ->(t) { t.field "alt_created_at", "DateTime", indexing_only: true }) do |t|
              expect(t.name).to eq "Widget"

              t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                r.equivalent_field "alt_created_at", locally_named: "created_at"
              end
            end

            expect(source).to eq "alt_created_at"

            expect {
              rollover_timestamp_value_source_for_widget_update_target_of("WidgetWorkspace", on_widget_workspace_type: ->(t) { t.field "alt_created_at", "DateTime", graphql_only: true }) do |t|
                expect(t.name).to eq "Widget"

                t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                  r.equivalent_field "alt_created_at", locally_named: "created_at"
                end
              end
            }.to raise_error Errors::SchemaError, a_string_including("`WidgetWorkspace.alt_created_at` (referenced from an `equivalent_field` defined on `Widget.workspace`) does not exist")
          end

          it "supports nested fields as a `routing_value_source`" do
            source = rollover_timestamp_value_source_for_widget_update_target_of("WidgetWorkspace") do |t|
              expect(t.name).to eq "Widget"

              t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                r.equivalent_field "nested.timestamp", locally_named: "created_at"
              end
            end

            expect(source).to eq "nested.timestamp"
          end

          def rollover_timestamp_value_source_for_widget_update_target_of(type, created_at_field_opts: {}, **options)
            update_targets = update_targets_for(type, on_widgets_index: ->(index) { index.rollover :yearly, "created_at" }, **options) do |t|
              t.field "created_at", "DateTime", **created_at_field_opts

              t.field "workspace_name", "String" do |f|
                f.sourced_from "workspace", "name"
              end

              yield t
            end

            expect(update_targets.count { |t| t.type == "Widget" }).to eq(1)
            widget_target = update_targets.find { |t| t.type == "Widget" }
            widget_target.rollover_timestamp_value_source
          end
        end

        def expect_widget_update_target_with(
          update_targets,
          id_source:,
          top_level_fields_params:,
          relationship:, routing_value_source: nil,
          rollover_timestamp_value_source: nil,
          sourced_from_nested_params: SchemaArtifacts::RuntimeMetadata::SourcedFromNestedParams::EMPTY
        )
          expect(update_targets.count { |t| t.type == "Widget" }).to eq(1)
          widget_target = update_targets.find { |t| t.type == "Widget" }

          expect(widget_target).not_to eq nil
          expect(widget_target.type).to eq "Widget"
          expect(widget_target.relationship).to eq relationship
          expect(widget_target.script_id).to eq(INDEX_DATA_UPDATE_SCRIPT_ID)
          expect(widget_target.id_source).to eq id_source
          expect(widget_target.routing_value_source).to eq(routing_value_source)
          expect(widget_target.rollover_timestamp_value_source).to eq(rollover_timestamp_value_source)
          expect(widget_target.top_level_fields_params).to eq(top_level_fields_params)
          expect(widget_target.sourced_from_nested_params).to eq(sourced_from_nested_params)
          expect(widget_target.metadata_params).to eq(standard_metadata_params(relationship: relationship))
        end

        describe "validations" do
          context "on `has_had_multiple_sources!` usage" do
            it "raises an error when `sourced_from` is used but `has_had_multiple_sources!` is not called on the index" do
              expect {
                object_type_metadata_for "Widget" do |s|
                  s.object_type "Widget" do |t|
                    t.field "id", "ID!"
                    t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                    t.field "workspace_name", "String" do |f|
                      f.sourced_from "workspace", "name"
                    end

                    t.index "widgets"
                  end

                  s.object_type "WidgetWorkspace" do |t|
                    t.field "id", "ID!"
                    t.field "name", "String"
                    t.field "widget_ids", "[ID!]!"
                    t.index "widget_workspaces"
                  end
                end
              }.to raise_error Errors::SchemaError, a_string_including(
                "Type `Widget` has `sourced_from` fields (via `Widget.workspace`) but its index `widgets` has not been configured with `has_had_multiple_sources!`",
                "To resolve this, add `i.has_had_multiple_sources!` within the `t.index \"widgets\"` block",
                "This flag is required because indices with multiple sources can contain incomplete documents",
                "Once set, this flag should remain even if you later remove all `sourced_from` fields"
              )
            end

            it "allows `has_had_multiple_sources!` to be called on an index that has no current `sourced_from` fields" do
              expect {
                object_type_metadata_for "Widget" do |s|
                  s.object_type "Widget" do |t|
                    t.field "id", "ID!"
                    t.index "widgets" do |i|
                      i.has_had_multiple_sources!
                    end
                  end
                end
              }.not_to raise_error
            end
          end

          context "on the relationship" do
            it "respects a type name override on the related type" do
              expect {
                update_targets_for("Widget", type_name_overrides: {WidgetWorkspace: "WorkspaceForWidget"}) do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "workspace_id", dir: :out
                  expect(t.fields_with_sources).to be_empty
                end
              }.not_to raise_error
            end

            it "raises an error if a relationship referenced from a `sourced_from` uses `additional_filter`" do
              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |rel|
                    rel.additional_filter is_enabled: {equal_to_any_of: [true]}
                  end

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error_about_workspace_relationship("uses an `additional_filter`, but `sourced_from` is not supported on relationships with `additional_filter`.")
            end

            it "raises an error if the referenced relationship is not defined" do
              expect {
                update_targets_for("Widget") do |t|
                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error_about_workspace_relationship("is not defined. Is it misspelled?")
            end

            it "raises an error if the referenced relationship is a normal field instead of a `relates_to_one` field", :dont_validate_graphql_schema do
              expect {
                update_targets_for("Widget") do |t|
                  t.field "workspace", "WidgetWorkspace"

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error_about_workspace_relationship("is not a relationship. It must be defined using `relates_to_one` or `relates_to_many`.")
            end

            it "raises an error if a relationship referenced from a `sourced_from` field is a `relates_to_many` since we don't yet support that" do
              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_many "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in, singular: "workspace"

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error_about_workspace_relationship("is a `relates_to_many` relationship, but `sourced_from` is only supported on a `relates_to_one` relationship.")
            end

            it "still allows other relationships to be defined as a `relates_to_many`" do
              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_many "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in, singular: "workspace"
                  expect(t.fields_with_sources).to be_empty
                end
              }.not_to raise_error
            end

            it "raises an error if the referenced relationship uses an outbound foreign key instead of an inbound foreign key since we don't yet support that type of foreign key" do
              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "workspace_id", dir: :out

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error_about_workspace_relationship("has an outbound foreign key (`dir: :out`), but `sourced_from` is only supported via inbound foreign key (`dir: :in`) relationships.")
            end

            it "still allows other relationships to be defined with an outbound foreign key" do
              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "workspace_id", dir: :out
                  expect(t.fields_with_sources).to be_empty
                end
              }.not_to raise_error
            end

            it "raises an error if the related type does not exist, regardless of whether there are any `sourced_from` fields or not", :dont_validate_graphql_schema do
              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspaceTypo", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error_about_workspace_relationship("references an unknown type: `WidgetWorkspaceTypo`. Is it misspelled?")

              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspaceTypo", via: "widget_ids", dir: :in
                  expect(t.fields_with_sources).to be_empty
                end
              }.to raise_error_about_workspace_relationship(
                "references an unknown type: `WidgetWorkspaceTypo`. Is it misspelled?",
                sourced_fields: false
              )
            end

            it "raises an error if the related type exists but is a scalar type, regardless of whether there are any `sourced_from` fields or not" do
              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "DateTime", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error_about_workspace_relationship(
                "references a type which is not an object type: `DateTime`. Only object types can be used in relations."
              )

              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "DateTime", via: "widget_ids", dir: :in
                  expect(t.fields_with_sources).to be_empty
                end
              }.to raise_error_about_workspace_relationship(
                "references a type which is not an object type: `DateTime`. Only object types can be used in relations.",
                sourced_fields: false
              )
            end

            it "raises an error if the related type exists but is a list type, regardless of whether there are any `sourced_from` fields or not" do
              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "[WidgetWorkspace]", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error_about_workspace_relationship(
                "references a type which is not an object type: `[WidgetWorkspace]`. Only object types can be used in relations."
              )

              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "[WidgetWorkspace]", via: "widget_ids", dir: :in
                  expect(t.fields_with_sources).to be_empty
                end
              }.to raise_error_about_workspace_relationship(
                "references a type which is not an object type: `[WidgetWorkspace]`. Only object types can be used in relations.",
                sourced_fields: false
              )
            end

            it "raises an error if the related type exists but is an enum type, regardless of whether there are any `sourced_from` fields or not" do
              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "Color", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error_about_workspace_relationship(
                "references a type which is not an object type: `Color`. Only object types can be used in relations."
              )

              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "Color", via: "widget_ids", dir: :in
                  expect(t.fields_with_sources).to be_empty
                end
              }.to raise_error_about_workspace_relationship(
                "references a type which is not an object type: `Color`. Only object types can be used in relations.",
                sourced_fields: false
              )
            end

            it "raises an error if the related type exists but is a non-indexed object type, regardless of whether there are any `sourced_from` fields or not" do
              expect {
                update_targets_for("Widget", index_widget_workspaces: false) do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error_about_workspace_relationship(
                "references a type which is not a root document type: `WidgetWorkspace`. Only root document types can be used in relations."
              )

              expect {
                update_targets_for("Widget", index_widget_workspaces: false) do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in
                  expect(t.fields_with_sources).to be_empty
                end
              }.to raise_error_about_workspace_relationship(
                "references a type which is not a root document type: `WidgetWorkspace`. Only root document types can be used in relations.",
                sourced_fields: false
              )
            end

            it "raises an error if an inbound foreign key field does not exist on the related type, regardless of whether there are any `sourced_from` fields or not" do
              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "unknown_id", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error_about_workspace_relationship(
                "uses `WidgetWorkspace.unknown_id` as the foreign key, but that field does not exist as an indexing field."
              )

              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "unknown_id", dir: :in
                  expect(t.fields_with_sources).to be_empty
                end
              }.to raise_error_about_workspace_relationship(
                "uses `WidgetWorkspace.unknown_id` as the foreign key, but that field does not exist as an indexing field.",
                sourced_fields: false
              )
            end

            it "raises an error if an inbound foreign key field exists as a GraphQL-only field on the related type, regardless of whether there are any `sourced_from` fields or not" do
              expect {
                update_targets_for("Widget", on_widget_workspace_type: ->(t) { t.field "gql_only_id", "ID", graphql_only: true }) do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "gql_only_id", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error_about_workspace_relationship(
                "uses `WidgetWorkspace.gql_only_id` as the foreign key, but that field does not exist as an indexing field."
              )

              expect {
                update_targets_for("Widget", on_widget_workspace_type: ->(t) { t.field "gql_only_id", "ID", graphql_only: true }) do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "gql_only_id", dir: :in
                  expect(t.fields_with_sources).to be_empty
                end
              }.to raise_error_about_workspace_relationship(
                "uses `WidgetWorkspace.gql_only_id` as the foreign key, but that field does not exist as an indexing field.",
                sourced_fields: false
              )
            end

            it "raises an error if an inbound foreign key field is not an `ID`, regardless of whether there are any `sourced_from` fields or not" do
              expect {
                update_targets_for("Widget", on_widget_workspace_type: ->(t) { t.field "numeric_id", "Int" }) do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "numeric_id", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error_about_workspace_relationship(
                "uses `WidgetWorkspace.numeric_id` as the foreign key, but that field is not an `ID` field as expected."
              )

              expect {
                update_targets_for("Widget", on_widget_workspace_type: ->(t) { t.field "numeric_id", "Int" }) do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "numeric_id", dir: :in
                  expect(t.fields_with_sources).to be_empty
                end
              }.to raise_error_about_workspace_relationship(
                "uses `WidgetWorkspace.numeric_id` as the foreign key, but that field is not an `ID` field as expected.",
                sourced_fields: false
              )
            end

            it "raises an error if an outbound foreign key field is not an `ID`" do
              expect {
                update_targets_for("Widget", on_widget_workspace_type: ->(t) {
                  t.field "numeric_id", "Int"
                  t.relates_to_one "widget", "Widget", via: "numeric_id", dir: :out
                })
              }.to raise_error Errors::SchemaError, a_string_including(
                "`WidgetWorkspace.widget` uses `WidgetWorkspace.numeric_id` as the foreign key, but that field is not an `ID` field as expected."
              )
            end

            it "does not raise an error if the outbound foreign key field is inferred instead of explicitly defined" do
              expect {
                update_targets_for("Widget", on_widget_workspace_type: ->(t) {
                  t.relates_to_one "widget", "Widget", via: "numeric_id", dir: :out
                })
              }.not_to raise_error
            end

            it "allows a foreign key whose type is nested inside of an `object` array" do
              expect {
                object_type_metadata_for "WidgetWorkspace" do |s|
                  s.object_type "WorkspaceReference" do |t|
                    t.field "workspace_id", "ID!"
                  end

                  s.object_type "Widget" do |t|
                    t.field "id", "ID!"
                    t.field "workspaces", "[WorkspaceReference!]!" do |f|
                      f.mapping type: "object"
                    end
                    t.index "widgets"
                  end

                  s.object_type "WidgetWorkspace" do |t|
                    t.field "id", "ID!"
                    t.relates_to_many "widgets", "Widget", via: "workspaces.workspace_id", dir: :in, singular: "widget"
                    t.index "widget_workspaces"
                  end
                end
              }.not_to raise_error
            end

            it "allows a foreign key whose type is nested inside of a `nested` array" do
              expect {
                object_type_metadata_for "WidgetWorkspace" do |s|
                  s.object_type "WorkspaceReference" do |t|
                    t.field "workspace_id", "ID!"
                  end

                  s.object_type "Widget" do |t|
                    t.field "id", "ID!"
                    t.field "workspaces", "[WorkspaceReference!]!" do |f|
                      f.mapping type: "nested"
                    end
                    t.index "widgets"
                  end

                  s.object_type "WidgetWorkspace" do |t|
                    t.field "id", "ID!"
                    t.relates_to_many "widgets", "Widget", via: "workspaces.workspace_id", dir: :in, singular: "widget"
                    t.index "widget_workspaces"
                  end
                end
              }.not_to raise_error
            end

            it "validates relationships on unindexed object types" do
              expect {
                object_type_metadata_for "WidgetWorkspace" do |s|
                  s.object_type "WorkspaceReference" do |t|
                    t.field "workspace_id", "ID!"
                  end

                  s.object_type "Widget" do |t|
                    t.field "id", "ID!"
                    t.field "workspaces", "[WorkspaceReference!]!" do |f|
                      f.mapping type: "object"
                    end
                    t.index "widgets"
                  end

                  s.object_type "WidgetWorkspace" do |t|
                    t.field "id", "ID!"
                    t.relates_to_many "widgets", "Widget", via: "workspaces.invalid_key", dir: :in, singular: "widget"
                  end
                end
              }.to raise_error Errors::SchemaError, a_string_including(
                "`WidgetWorkspace.widgets` uses `Widget.workspaces.invalid_key` as the foreign key",
                "but that field does not exist as an indexing field"
              )
            end
          end

          context "on `equivalent_field` definitions" do
            it "does not allow `equivalent_field` definitions to stomp each other" do
              expect {
                update_targets_for("WidgetWorkspace") do |t|
                  expect(t.name).to eq "Widget"

                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                    r.equivalent_field "created_at1", locally_named: "created_at"
                    r.equivalent_field "created_at2", locally_named: "created_at"
                  end
                end
              }.to raise_error Errors::SchemaError, a_string_including(
                "`equivalent_field` has been called multiple times on `Widget.workspace",
                'same `locally_named` value ("created_at")'
              )
            end

            it "raises a clear error if the configured `equivalent_field` does not exist" do
              expect {
                update_targets_for("WidgetWorkspace") do |t|
                  expect(t.name).to eq "Widget"

                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                    r.equivalent_field "unknown_id", locally_named: "id"
                  end

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end
                end
              }.to raise_error Errors::SchemaError, a_string_including(
                "Field `WidgetWorkspace.unknown_id` (referenced from an `equivalent_field` defined on `Widget.workspace`) does not exist. Either define it or correct the `equivalent_field` definition."
              )
            end

            it "raises a clear error if the `locally_named` field of a configured `equivalent_field` does not exist" do
              expect {
                update_targets_for("WidgetWorkspace") do |t|
                  expect(t.name).to eq "Widget"

                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                    r.equivalent_field "workspace_owner_id", locally_named: "unknown_id"
                  end

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end
                end
              }.to raise_error Errors::SchemaError, a_string_including(
                "Field `Widget.unknown_id` (referenced from an `equivalent_field` defined on `Widget.workspace`) does not exist. Either define it or correct the `equivalent_field` definition."
              )
            end

            it "requires both sides of an `equivalent_field` to have the same type" do
              expect {
                update_targets_for("WidgetWorkspace") do |t|
                  expect(t.name).to eq "Widget"

                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                    r.equivalent_field "name", locally_named: "id"
                  end

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end
                end
              }.to raise_error Errors::SchemaError, a_string_including(
                "Field `WidgetWorkspace.name: String` is defined as an equivalent of `Widget.id: ID!` via an `equivalent_field` definition on `Widget.workspace`, but their types do not agree. To continue, change one or the other so that they agree."
              )
            end

            it "allows the two sides of an `equivalent_field` to differ in terms of nullability" do
              expect {
                update_targets_for("WidgetWorkspace", widget_workspace_name: "String!", widget_name: "String") do |t|
                  expect(t.name).to eq "Widget"

                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                    r.equivalent_field "name", locally_named: "name"
                  end

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end
                end
              }.not_to raise_error
            end

            it "does not allow the two sides of an `equivalent_field` to differ in terms of list wrappings" do
              expect {
                update_targets_for("WidgetWorkspace", widget_workspace_name: "String", widget_name: "[String]") do |t|
                  expect(t.name).to eq "Widget"

                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in do |r|
                    r.equivalent_field "name", locally_named: "name"
                  end

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end
                end
              }.to raise_error Errors::SchemaError, a_string_including(
                "Field `WidgetWorkspace.name: String` is defined as an equivalent of `Widget.name: [String]` via an `equivalent_field` definition on `Widget.workspace`, but their types do not agree. To continue, change one or the other so that they agree."
              )
            end

            it "does not interfere with the non-nullability of a `relates_to_one` field" do
              expect {
                update_targets_for("WidgetWorkspace") do |t|
                  expect(t.name).to eq "Widget"

                  t.relates_to_one "workspace", "WidgetWorkspace!", via: "widget_ids", dir: :in do |r|
                    r.equivalent_field "name", locally_named: "name"
                  end

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end
                end
              }.not_to raise_error
            end
          end

          context "on the referenced field" do
            it "raises an error if the referenced field doesn't exist on the related type" do
              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name2"
                  end

                  t.field "workspace_created_at", "DateTime" do |f|
                    f.sourced_from "workspace", "created_at3"
                  end
                end
              }.to raise_error a_string_including(
                "1. `Widget.workspace_name` has an invalid `sourced_from` argument: `WidgetWorkspace.name2` does not exist as an indexing field.",
                "2. `Widget.workspace_created_at` has an invalid `sourced_from` argument: `WidgetWorkspace.created_at3` does not exist as an indexing field."
              )
            end

            it "allows the referenced field to be an `indexing_only` field since it must be ingested but need not be exposed in GraphQL" do
              expect {
                update_targets_for("Widget", widget_workspace_name_opts: {indexing_only: true}) do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end
                end
              }.not_to raise_error
            end

            it "does not allow the referenced field to be a `graphql_only_field` field" do
              expect {
                update_targets_for("Widget", widget_workspace_name_opts: {graphql_only: true}) do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end
                end
              }.to raise_error a_string_including(
                "`Widget.workspace_name` has an invalid `sourced_from` argument: `WidgetWorkspace.name` does not exist as an indexing field."
              )
            end

            it "raises an error if any part of nested field path doesn't exist" do
              try_sourced_from_field_path = lambda do |field_path|
                update_targets_for("WidgetWorkspace") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", field_path
                  end
                end
              end

              # verify that `nested.further_nested.name` is correct.
              expect { try_sourced_from_field_path.call("nested.further_nested.name") }.not_to raise_error

              expect {
                try_sourced_from_field_path.call("nesteth.further_nested.name")
              }.to raise_error a_string_including(
                "1. `Widget.workspace_name` has an invalid `sourced_from` argument: `WidgetWorkspace.nesteth.further_nested.name` could not be resolved"
              )

              expect {
                try_sourced_from_field_path.call("nested.further_nesteth.name")
              }.to raise_error a_string_including(
                "1. `Widget.workspace_name` has an invalid `sourced_from` argument: `WidgetWorkspace.nested.further_nesteth.name` could not be resolved"
              )

              expect {
                try_sourced_from_field_path.call("nested.further_nested.missing")
              }.to raise_error a_string_including(
                "1. `Widget.workspace_name` has an invalid `sourced_from` argument: `WidgetWorkspace.nested.further_nested.missing` could not be resolved"
              )
            end

            it "raises an error if an empty field path is provided" do
              expect {
                update_targets_for("WidgetWorkspace") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", ""
                  end
                end
              }.to raise_error a_string_including(
                "1. `Widget.workspace_name` has an invalid `sourced_from` argument: `WidgetWorkspace.` does not exist as an indexing field."
              )
            end

            it "raises an error if any of the parent parts of the field path refer to non-object fields" do
              expect {
                update_targets_for("WidgetWorkspace") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name.nested"
                  end
                end
              }.to raise_error a_string_including(
                "1. `Widget.workspace_name` has an invalid `sourced_from` argument: `WidgetWorkspace.name.nested` could not be resolved"
              )
            end

            it "raises an error if any of the parts of a nested field are list fields" do
              expect {
                update_targets_for("WidgetWorkspace", widget_workspace_nested_1_further_nested: "[WidgetWorkspaceNested2]") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "nested.further_nested.name"
                  end
                end
              }.to raise_error a_string_including(
                "`Widget.workspace_name` has an invalid `sourced_from` argument: `WidgetWorkspace.nested.further_nested.name` could not be resolved",
                "some parts do not exist on their respective types as non-list fields"
              )
            end
          end

          context "on the referenced field's type" do
            it "requires the referenced field to have the same GraphQL type as the `sourced_from` field" do
              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "DateTime" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "String" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error a_string_including(
                "1. The type of `Widget.workspace_name` is `DateTime`, but the type of its source (`WidgetWorkspace.name`) is `String`. These must agree to use `sourced_from`.",
                "2. The type of `Widget.workspace_created_at` is `String`, but the type of its source (`WidgetWorkspace.created_at`) is `DateTime`. These must agree to use `sourced_from`."
              )
            end

            it "allows a `sourced_from` field to be nullable even if its referenced field is not" do
              expect {
                update_targets_for("Widget", widget_workspace_name: "String!") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end
                end
              }.not_to raise_error
            end

            it "does not allow a `sourced_from` field to be non-nullable when its referenced field is nullable" do
              expect {
                update_targets_for("Widget", widget_workspace_name: "String") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String!" do |f|
                    f.sourced_from "workspace", "name"
                  end
                end
              }.to raise_error a_string_including(
                "The type of `Widget.workspace_name` (`String!`) is not nullable, but this is not allowed for `sourced_from` fields since the value will be `null` before the related type's event is ingested."
              )
            end

            it "does not allow a `sourced_from` field to be non-nullable even if its referenced field is non-nullable because if the related event is ingested 2nd the value will initially be null" do
              expect {
                update_targets_for("Widget", widget_workspace_name: "String!") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String!" do |f|
                    f.sourced_from "workspace", "name"
                  end
                end
              }.to raise_error a_string_including(
                "The type of `Widget.workspace_name` (`String!`) is not nullable, but this is not allowed for `sourced_from` fields since the value will be `null` before the related type's event is ingested."
              )
            end

            it "does not consider a list and scalar field to be the same type" do
              expect {
                update_targets_for("Widget", widget_workspace_name: "[String]") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.sourced_from "workspace", "name"
                  end

                  t.field "workspace_created_at", "[DateTime]" do |f|
                    f.sourced_from "workspace", "created_at"
                  end
                end
              }.to raise_error a_string_including(
                "1. The type of `Widget.workspace_name` is `String`, but the type of its source (`WidgetWorkspace.name`) is `[String]`. These must agree to use `sourced_from`.",
                "2. The type of `Widget.workspace_created_at` is `[DateTime]`, but the type of its source (`WidgetWorkspace.created_at`) is `DateTime`. These must agree to use `sourced_from`."
              )
            end

            it "otherwise supports list fields" do
              expect {
                update_targets_for("Widget", widget_workspace_name: "[String]") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "[String]" do |f|
                    f.sourced_from "workspace", "name"
                  end
                end
              }.not_to raise_error
            end

            it "allows the referenced field to have a different mapping type from the `sourced_from` field" do
              expect {
                update_targets_for("Widget") do |t|
                  t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

                  t.field "workspace_name", "String" do |f|
                    f.mapping type: "text"
                    f.sourced_from "workspace", "name"
                  end
                end
              }.not_to raise_error
            end
          end

          def raise_error_about_workspace_relationship(details, sourced_fields: true)
            expected_string =
              if sourced_fields
                "`Widget.workspace` (referenced from `sourced_from` on field(s): `workspace_name`, `workspace_created_at`) #{details}"
              else
                "`Widget.workspace` #{details}"
              end

            raise_error Errors::SchemaError, a_string_including(expected_string)
          end
        end

        describe "nested `sourced_from` update targets" do
          it "dumps a nested update target on the source type, keyed by the qualified relationship" do
            expect_statline_update_target_with(nested_sourced_from_schema)
          end

          it "omits `path_identifier_params` for a non-list (object) embedding field, since there is no element to match" do
            expect_statline_update_target_with(nested_sourced_from_schema(players_field: "Player!"), path_identifier_params: {})
          end

          it "bundles every `sourced_from` field on the nested type into `field_params`" do
            metadata = nested_sourced_from_schema(
              on_player: ->(t) {
                t.field "assists", "Int" do |f|
                  f.sourced_from "statLine", "assists"
                end
              },
              on_statline: ->(t) { t.field "assists", "Int" }
            )

            expect_statline_update_target_with(metadata, field_params: {
              "goals" => dynamic_param_with(source_path: "goals", cardinality: :one),
              "assists" => dynamic_param_with(source_path: "assists", cardinality: :one)
            })
          end

          it "resolves a `sourced_from` field from a nested path on the source type" do
            metadata = nested_sourced_from_schema(
              player_goals_source: "stats.goals",
              on_statline: ->(t) { t.field "stats", "StatLineStats" }
            ) do |s|
              s.object_type "StatLineStats" do |t|
                t.field "goals", "Int"
              end
            end

            expect_statline_update_target_with(metadata, field_params: {
              "goals" => dynamic_param_with(source_path: "stats.goals", cardinality: :one)
            })
          end

          it "keys `field_params` by the `sourced_from` field's `name_in_index`" do
            metadata = nested_sourced_from_schema(
              on_player: ->(t) {
                t.field "assists", "Int", name_in_index: "assists_in_index" do |f|
                  f.sourced_from "statLine", "assists"
                end
              },
              on_statline: ->(t) { t.field "assists", "Int" }
            )

            expect_statline_update_target_with(metadata, field_params: {
              "goals" => dynamic_param_with(source_path: "goals", cardinality: :one),
              "assists_in_index" => dynamic_param_with(source_path: "assists", cardinality: :one)
            })
          end

          context "on a root type that uses custom routing" do
            it "determines the `routing_value_source` from an `equivalent_field` configured on the root relationship" do
              metadata = nested_sourced_from_schema(
                on_team: ->(t) { t.field "team_owner_id", "ID!" },
                on_teams_index: ->(i) { i.route_with "team_owner_id" },
                on_statlines_relationship: ->(r) {
                  # A nested routing source forces the field-path resolver to descend through the parent field.
                  r.equivalent_field "stats.owner_id", locally_named: "team_owner_id"
                },
                on_statline: ->(t) { t.field "stats", "StatLineStats" }
              ) do |s|
                s.object_type "StatLineStats" do |t|
                  t.field "owner_id", "ID"
                end
              end

              expect_statline_update_target_with(metadata, routing_value_source: "stats.owner_id")
            end

            it "raises a clear error when the equivalent field is a `graphql_only` field with no indexing path" do
              expect {
                nested_sourced_from_schema(
                  on_team: ->(t) { t.field "team_owner_id", "ID!" },
                  on_teams_index: ->(i) { i.route_with "team_owner_id" },
                  on_statlines_relationship: ->(r) { r.equivalent_field "owner_id", locally_named: "team_owner_id" },
                  on_statline: ->(t) { t.field "owner_id", "ID", graphql_only: true }
                )
              }.to raise_error Errors::SchemaError, a_string_including(
                "`StatLine.owner_id` (referenced from an `equivalent_field` defined on `Team.statLines`) does not exist"
              )
            end

            it "raises a clear error when no `equivalent_field` is configured for the custom routing field" do
              expect {
                nested_sourced_from_schema(
                  on_team: ->(t) { t.field "team_owner_id", "ID!" },
                  on_teams_index: ->(i) { i.route_with "team_owner_id" }
                )
              }.to raise_error Errors::SchemaError, a_string_including(
                "Cannot update `Team` documents with data from related `statLines` events",
                "`Team` uses custom shard routing but we don't know what `statLines` field to use to route the `Team` update requests",
                "add a call like this to the `Team.statLines` relationship definition",
                '`rel.equivalent_field "[StatLine field]", locally_named: "team_owner_id"`'
              )
            end
          end

          context "on a root type that uses a rollover index" do
            it "determines the `rollover_timestamp_value_source` from an `equivalent_field` configured on the root relationship" do
              metadata = nested_sourced_from_schema(
                on_team: ->(t) { t.field "team_created_at", "DateTime" },
                on_teams_index: ->(i) { i.rollover :yearly, "team_created_at" },
                on_statlines_relationship: ->(r) { r.equivalent_field "created_at", locally_named: "team_created_at" },
                on_statline: ->(t) { t.field "created_at", "DateTime" }
              )

              expect_statline_update_target_with(metadata, rollover_timestamp_value_source: "created_at")
            end

            it "raises a clear error when no `equivalent_field` is configured for the rollover timestamp field" do
              expect {
                nested_sourced_from_schema(
                  on_team: ->(t) { t.field "team_created_at", "DateTime" },
                  on_teams_index: ->(i) { i.rollover :yearly, "team_created_at" }
                )
              }.to raise_error Errors::SchemaError, a_string_including(
                "Cannot update `Team` documents with data from related `statLines` events",
                "`Team` uses a rollover index but we don't know what `statLines` timestamp field to use to select an index for the `Team` update requests",
                "add a call like this to the `Team.statLines` relationship definition",
                '`rel.equivalent_field "[StatLine field]", locally_named: "team_created_at"`'
              )
            end
          end

          describe "validations" do
            it "raises an error when the nested `sourced_from` field does not exist on the sourced type" do
              expect {
                nested_sourced_from_schema(player_goals_source: "nonexistent")
              }.to raise_error Errors::SchemaError, a_string_including(
                "`Player.goals` has an invalid `sourced_from` argument: `StatLine.nonexistent` does not exist as an indexing field."
              )
            end

            it "raises an error when the nested `sourced_from` field's type does not match its source's type" do
              expect {
                nested_sourced_from_schema(player_goals_type: "String")
              }.to raise_error Errors::SchemaError, a_string_including(
                "The type of `Player.goals` is `String`, but the type of its source (`StatLine.goals`) is `Int`. These must agree to use `sourced_from`."
              )
            end

            it "raises an error when the root index has not been configured with `has_had_multiple_sources!`" do
              expect {
                nested_sourced_from_schema(multiple_sources: false)
              }.to raise_error Errors::SchemaError, a_string_including(
                "Type `Team` has `sourced_from` fields (via `Player.statLine`) but its index `teams` has not been configured with `has_had_multiple_sources!`"
              )
            end

            it "raises an error when the leaf relationship is `relates_to_many`" do
              expect {
                object_type_metadata_for "Team" do |s|
                  s.object_type "Team" do |t|
                    t.field "id", "ID!"
                    t.field "players", "[Player!]!" do |f|
                      f.mapping type: "object"
                    end
                    t.relates_to_many "statLines", "StatLine", via: "teamId", dir: :in, indexing_only: true
                    t.index("teams") { |i| i.has_had_multiple_sources! }
                  end

                  s.object_type "Player" do |t|
                    t.field "id", "ID!"
                    t.field "goals", "Int" do |f|
                      f.sourced_from "statLines", "goals"
                    end
                    t.relates_to_many "statLines", "StatLine", via: "playerId", dir: :in, indexing_only: true do |r|
                      r.parent_relationship "Team", "statLines"
                    end
                  end

                  s.object_type "StatLine" do |t|
                    t.field "id", "ID!"
                    t.field "teamId", "ID"
                    t.field "playerId", "ID"
                    t.field "goals", "Int"
                    t.index "stat_lines"
                  end
                end
              }.to raise_error Errors::SchemaError, a_string_including(
                "`Player.statLines` (referenced from `sourced_from` on field(s): `goals`) is a `relates_to_many` relationship, but `sourced_from` is only supported on a `relates_to_one` relationship."
              )
            end
          end
        end

        describe "`parent_relationship` validations" do
          it "accepts an explicit `embedded_at:` to identify the embedding field" do
            metadata = nested_sourced_from_schema(
              on_player_relationship: ->(r) { r.parent_relationship "Team", "statLines", embedded_at: "players" }
            )

            expect_statline_update_target_with(metadata)
          end

          it "discovers an embedding field declared with `indexing_only: true`" do
            # An `indexing_only: true` field is absent from `graphql_fields_by_name` but present in
            # `indexing_fields_by_name_in_index`, so this only resolves when the latter is used.
            metadata = nested_sourced_from_schema(players_field: nil, on_team: ->(t) {
              t.field "players", "[Player!]!", indexing_only: true do |f|
                f.mapping type: "object"
              end
            })

            expect_statline_update_target_with(metadata)
          end

          it "resolves an `embedded_at` by public field name even when the embedding field has a distinct `name_in_index`" do
            metadata = nested_sourced_from_schema(
              on_team: ->(t) {
                t.field "players", "[Player!]!", name_in_index: "the_players" do |f|
                  f.mapping type: "object"
                end
              },
              players_field: nil,
              on_player_relationship: ->(r) { r.parent_relationship "Team", "statLines", embedded_at: "players" }
            )

            expect_statline_update_target_with(metadata, relationship: "the_players.statLine")
          end

          context "when the embedding field is reached via a dotted `embedded_at` path" do
            it "descends an object segment to a leaf list segment, keying the target by the full qualified relationship" do
              metadata = nested_sourced_from_schema(
                embed_players_under: "TeamNestedFields",
                on_player_relationship: ->(r) { r.parent_relationship "Team", "statLines", embedded_at: "nested.players" }
              )

              expect_statline_update_target_with(metadata, relationship: "nested.players.statLine")
            end

            it "omits `path_identifier_params` when the leaf of the dotted path is an object (not a list)" do
              metadata = nested_sourced_from_schema(
                embed_players_under: "TeamNestedFields",
                players_field: "Player!",
                on_player_relationship: ->(r) { r.parent_relationship "Team", "statLines", embedded_at: "nested.players" }
              )

              expect_statline_update_target_with(metadata, relationship: "nested.players.statLine", path_identifier_params: {})
            end

            it "raises a clear error pointing at the multi-link solution when an intermediate segment is a list" do
              expect {
                nested_sourced_from_schema(
                  embed_players_under: "[TeamNestedFields!]!",
                  on_player_relationship: ->(r) { r.parent_relationship "Team", "statLines", embedded_at: "nested.players" }
                )
              }.to raise_error Errors::SchemaError, a_string_including(
                "`Player.statLine` embeds through list field `Team.nested` via `parent_relationship`, but only the final embedding field may be a list.",
                "give its embedded type its own `relates_to_one`/`relates_to_many` to the source type with a `parent_relationship`"
              )
            end

            it "raises a clear error when the dotted path does not resolve to a field" do
              expect {
                nested_sourced_from_schema(
                  embed_players_under: "TeamNestedFields",
                  on_player_relationship: ->(r) { r.parent_relationship "Team", "statLines", embedded_at: "nested.nonexistent" }
                )
              }.to raise_error Errors::SchemaError, a_string_including(
                "`Player.statLine` references field `Team.nested.nonexistent` via `parent_relationship`, but that field does not exist."
              )
            end
          end

          it "raises an error when `parent_relationship` is called twice on the same relationship" do
            expect {
              nested_sourced_from_schema(
                on_player_relationship: ->(r) {
                  r.parent_relationship "Team", "statLines"
                  r.parent_relationship "Team", "statLines"
                }
              )
            }.to raise_error Errors::SchemaError, a_string_including(
              "`parent_relationship` has been called multiple times on `Player.statLine`"
            )
          end

          it "raises an error when `parent_relationship` is used without `indexing_only: true`" do
            expect {
              nested_sourced_from_schema(player_indexing_only: false)
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Player.statLine` uses `parent_relationship` but is not declared with `indexing_only: true`"
            )
          end

          it "raises an error when a circular parent chain is detected", :dont_validate_graphql_schema do
            expect {
              object_type_metadata_for "Team" do |s|
                s.object_type "Team" do |t|
                  t.field "id", "ID!"
                  t.field "players", "[Player!]!" do |f|
                    f.mapping type: "object"
                  end
                  t.relates_to_many "statLines", "StatLine", via: "teamId", dir: :in, indexing_only: true do |r|
                    r.parent_relationship "Player", "statLine"
                  end
                end

                s.object_type "Player" do |t|
                  t.field "id", "ID!"
                  t.field "teams", "[Team!]!" do |f|
                    f.mapping type: "object"
                  end
                  t.field "goals", "Int" do |f|
                    f.sourced_from "statLine", "goals"
                  end
                  t.relates_to_one "statLine", "StatLine", via: "playerId", dir: :in, indexing_only: true do |r|
                    r.parent_relationship "Team", "statLines"
                  end
                end

                s.object_type "StatLine" do |t|
                  t.field "id", "ID!"
                  t.field "teamId", "ID"
                  t.field "playerId", "ID"
                  t.field "goals", "Int"
                  t.index "stat_lines"
                end
              end
            }.to raise_error Errors::SchemaError, a_string_including(
              "creates a circular `parent_relationship` chain"
            )
          end

          it "resolves a chain spanning several levels" do
            # League -> Team -> Player -> GameAppearance is a 4-level `parent_relationship` chain (leaf
            # to root: GameAppearance's relationship walks up through Player and Team to the indexed
            # League). All four relationships relate to the same `StatLine` source type, so the chain is
            # valid. This can only resolve correctly if `resolve_chain` recurses through every level.
            metadata =
              object_type_metadata_for "StatLine" do |s|
                s.object_type "League" do |t|
                  t.field "id", "ID!"
                  t.field "teams", "[Team!]!" do |f|
                    f.mapping type: "object"
                  end
                  t.relates_to_many "statLines", "StatLine", via: "leagueId", dir: :in, indexing_only: true
                  t.index("leagues") { |i| i.has_had_multiple_sources! }
                end

                s.object_type "Team" do |t|
                  t.field "id", "ID!"
                  t.field "players", "[Player!]!" do |f|
                    f.mapping type: "object"
                  end
                  t.relates_to_many "statLines", "StatLine", via: "teamId", dir: :in, indexing_only: true do |r|
                    r.parent_relationship "League", "statLines"
                  end
                end

                s.object_type "Player" do |t|
                  t.field "id", "ID!"
                  t.field "gameAppearances", "[GameAppearance!]!" do |f|
                    f.mapping type: "object"
                  end
                  t.relates_to_many "statLines", "StatLine", via: "playerId", dir: :in, indexing_only: true do |r|
                    r.parent_relationship "Team", "statLines"
                  end
                end

                s.object_type "GameAppearance" do |t|
                  t.field "id", "ID!"
                  t.field "goals", "Int" do |f|
                    f.sourced_from "statLine", "goals"
                  end
                  t.relates_to_one "statLine", "StatLine", via: "gameAppearanceId", dir: :in, indexing_only: true do |r|
                    r.parent_relationship "Player", "statLines"
                  end
                end

                s.object_type "StatLine" do |t|
                  t.field "id", "ID!"
                  t.field "leagueId", "ID"
                  t.field "teamId", "ID"
                  t.field "playerId", "ID"
                  t.field "gameAppearanceId", "ID"
                  t.field "goals", "Int"
                  t.index "stat_lines"
                end
              end

            # The qualified relationship spans every embedding field from the root index down to the leaf,
            # proving the chain recursed through all four levels.
            expect(nested_update_targets_by_relationship(metadata).keys).to contain_exactly("teams.players.gameAppearances.statLine")
          end

          it "resolves a deeply nested chain mixing object dotted-path hops, multiple list links, and `name_in_index` renames" do
            # Embedding path (root -> leaf), * = list level. Each list level is its own `parent_relationship` link;
            # the object hops are folded into the links' dotted `embedded_at`s:
            #   Team .roster(the_roster) .squads* .lineup .players(the_players)* -> Player.goals (sourced)
            metadata =
              object_type_metadata_for "StatLine" do |s|
                s.object_type "Team" do |t|
                  t.field "id", "ID!"
                  t.field "roster", "Roster", name_in_index: "the_roster"
                  t.relates_to_many "statLines", "StatLine", via: "teamId", dir: :in, indexing_only: true
                  t.index("teams") { |i| i.has_had_multiple_sources! }
                end

                s.object_type "Roster" do |t|
                  t.field "squads", "[Squad!]!" do |f|
                    f.mapping type: "object"
                  end
                end

                s.object_type "Squad" do |t|
                  t.field "id", "ID!"
                  t.field "lineup", "Lineup"
                  t.relates_to_many "statLines", "StatLine", via: "squadId", dir: :in, indexing_only: true do |r|
                    r.parent_relationship "Team", "statLines", embedded_at: "roster.squads"
                  end
                end

                s.object_type "Lineup" do |t|
                  t.field "players", "[Player!]!", name_in_index: "the_players" do |f|
                    f.mapping type: "object"
                  end
                end

                s.object_type "Player" do |t|
                  t.field "id", "ID!"
                  t.field "goals", "Int" do |f|
                    f.sourced_from "statLine", "stats.goals"
                  end
                  t.relates_to_one "statLine", "StatLine", via: "playerId", dir: :in, indexing_only: true do |r|
                    r.parent_relationship "Squad", "statLines", embedded_at: "lineup.players"
                  end
                end

                s.object_type "StatLineStats" do |t|
                  t.field "goals", "Int"
                end

                s.object_type "StatLine" do |t|
                  t.field "id", "ID!"
                  t.field "teamId", "ID"
                  t.field "squadId", "ID"
                  t.field "playerId", "ID"
                  t.field "stats", "StatLineStats"
                  t.index "stat_lines"
                end
              end

            target = nested_update_targets_by_relationship(metadata).fetch("the_roster.squads.lineup.the_players.statLine")

            expect(target.type).to eq "Team"
            expect(target.id_source).to eq "teamId"
            expect(target.sourced_from_nested_params.field_params).to eq(
              "goals" => dynamic_param_with(source_path: "stats.goals", cardinality: :one)
            )
            # One identifier per list level; the object hops contribute none.
            expect(target.sourced_from_nested_params.path_identifier_params).to eq(
              "squadId" => dynamic_param_with(source_path: "squadId", cardinality: :one),
              "playerId" => dynamic_param_with(source_path: "playerId", cardinality: :one)
            )
          end

          it "raises an error when the parent type does not exist" do
            expect {
              nested_sourced_from_schema(
                on_player_relationship: ->(r) { r.parent_relationship "NonExistentType", "statLines" }
              )
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Player.statLine` references parent type `NonExistentType` via `parent_relationship`, but that type does not exist."
            )
          end

          it "raises an error when the parent relationship does not exist on the parent type" do
            # `Player` is indexed here in addition to being embedded on `Team`. This confirms that
            # `parent_relationship` chains are validated even for types that are both indexed and
            # embedded (not just non-indexed embedded types).
            expect {
              nested_sourced_from_schema(
                index_players: true,
                on_player_relationship: ->(r) { r.parent_relationship "Team", "nonExistentRelationship" }
              )
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Player.statLine` references parent relationship `Team.nonExistentRelationship` via `parent_relationship`, but that relationship does not exist."
            )
          end

          it "raises an error when source types disagree across the chain" do
            expect {
              nested_sourced_from_schema(
                on_team: ->(t) {
                  t.relates_to_many "otherEvents", "OtherEvent", via: "teamId", dir: :in, indexing_only: true
                },
                on_player_relationship: ->(r) { r.parent_relationship "Team", "otherEvents" }
              ) do |s|
                s.object_type "OtherEvent" do |t|
                  t.field "id", "ID!"
                  t.field "teamId", "ID"
                  t.index "other_events"
                end
              end
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Player.statLine` relates to `StatLine`",
              "but its parent relationship `Team.otherEvents` relates to `OtherEvent`",
              "All relationships in a `parent_relationship` chain must relate to the same source type"
            )
          end

          it "raises an error when a relationship in the chain uses an outbound foreign key" do
            expect {
              nested_sourced_from_schema(player_statline_dir: :out, player_statline_via: "statLineId")
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Player.statLine` (referenced from `sourced_from` on field(s): `goals`) has an outbound foreign key (`dir: :out`), but `sourced_from` is only supported via inbound foreign key (`dir: :in`) relationships."
            )
          end

          it "raises an error when a relationship in the chain uses an `additional_filter`" do
            expect {
              nested_sourced_from_schema(
                on_player_relationship: ->(r) {
                  r.parent_relationship "Team", "statLines"
                  r.additional_filter status: "active"
                }
              )
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Player.statLine` (referenced from `sourced_from` on field(s): `goals`) uses an `additional_filter`, but `sourced_from` is not supported on relationships with `additional_filter`."
            )
          end

          it "raises an error when a non-leaf (root) relationship in the chain uses an `additional_filter`" do
            # Routability (inbound FK, no `additional_filter`) must hold for *every* relationship in the chain,
            # not just the leaf that backs the `sourced_from` field: each link routes the source event up to the
            # root document, so a filtered/outbound link anywhere would silently mismatch. Here we break the
            # *root* relationship (`Team.statLines`) — the leaf (`Player.statLine`) remains valid — to prove the
            # chain-wide validation covers non-leaf relationships and isn't narrowed to the leaf.
            expect {
              nested_sourced_from_schema(
                on_statlines_relationship: ->(r) { r.additional_filter status: "active" }
              )
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Team.statLines` (referenced from `sourced_from` on field(s): `goals`) uses an `additional_filter`, but `sourced_from` is not supported on relationships with `additional_filter`."
            )
          end

          it "raises an error when the chain terminates at a non-indexed type" do
            expect {
              nested_sourced_from_schema(index_teams: false)
            }.to raise_error Errors::SchemaError, a_string_including(
              "The `parent_relationship` chain from `Player.statLine` terminates at `Team`",
              "`Team` is not an indexed type",
              "The chain must terminate at an indexed type"
            )
          end

          it "raises an error when no embedding field is found on the parent type" do
            expect {
              nested_sourced_from_schema(players_field: nil)
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Player.statLine` declares `Team` as its parent type via `parent_relationship`, but `Team` has no field of type `Player`"
            )
          end

          it "raises an error when multiple embedding fields exist (ambiguous)" do
            expect {
              nested_sourced_from_schema(on_team: ->(t) {
                t.field "bench_players", "[Player!]!" do |f|
                  f.mapping type: "object"
                end
              })
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Team` has multiple fields of type `Player`",
              "has an ambiguous `parent_relationship`",
              "embedded_at:"
            )
          end

          it "uses `embedded_at:` to disambiguate when multiple embedding fields exist" do
            metadata = nested_sourced_from_schema(
              on_team: ->(t) {
                t.field "bench_players", "[Player!]!" do |f|
                  f.mapping type: "object"
                end
              },
              on_player_relationship: ->(r) { r.parent_relationship "Team", "statLines", embedded_at: "bench_players" }
            )

            # The qualified relationship reflects `bench_players`, confirming disambiguation chose that field
            # rather than the also-eligible `players`.
            expect_statline_update_target_with(metadata, relationship: "bench_players.statLine")
          end

          it "raises an error when an explicit `embedded_at:` references a non-existent field" do
            expect {
              nested_sourced_from_schema(
                on_player_relationship: ->(r) { r.parent_relationship "Team", "statLines", embedded_at: "nonExistentField" }
              )
            }.to raise_error Errors::SchemaError, a_string_including(
              "`Player.statLine` references field `Team.nonExistentField` via `parent_relationship`, but that field does not exist."
            )
          end
        end

        # Projects a source type's update targets to a `{qualified_relationship => target}` map, excluding the
        # type's own `__self` target — leaving one entry per `parent_relationship` chain backing `sourced_from`.
        def nested_update_targets_by_relationship(metadata)
          metadata
            .update_targets
            .to_h { |t| [t.relationship, t] }
            .except(SELF_RELATIONSHIP_NAME)
        end

        # Asserts the full nested `UpdateTarget` that `StatLine` events produce for `Team`, with defaults for the
        # common `nested_sourced_from_schema` case so each test overrides only the attributes it exercises.
        def expect_statline_update_target_with(
          metadata,
          relationship: "players.statLine",
          routing_value_source: nil,
          rollover_timestamp_value_source: nil,
          field_params: {"goals" => dynamic_param_with(source_path: "goals", cardinality: :one)},
          path_identifier_params: {"playerId" => dynamic_param_with(source_path: "playerId", cardinality: :one)}
        )
          targets = nested_update_targets_by_relationship(metadata)
          expect(targets.keys).to contain_exactly(relationship)

          target = targets.fetch(relationship)
          expect(target.type).to eq "Team"
          expect(target.relationship).to eq relationship
          expect(target.script_id).to eq(INDEX_DATA_UPDATE_SCRIPT_ID)
          expect(target.id_source).to eq "teamId"
          expect(target.routing_value_source).to eq(routing_value_source)
          expect(target.rollover_timestamp_value_source).to eq(rollover_timestamp_value_source)
          expect(target.top_level_fields_params).to eq({})
          expect(target.sourced_from_nested_params.field_params).to eq(field_params)
          expect(target.sourced_from_nested_params.path_identifier_params).to eq(path_identifier_params)
          expect(target.metadata_params).to eq(standard_metadata_params(relationship: relationship))
        end

        def nested_sourced_from_schema(
          on_team: nil,
          on_player: nil,
          on_statlines_relationship: nil,
          on_player_relationship: ->(r) { r.parent_relationship "Team", "statLines" },
          player_indexing_only: true,
          players_field: "[Player!]!",
          embed_players_under: nil,
          index_teams: true,
          index_players: false,
          multiple_sources: true,
          on_teams_index: nil,
          on_statline: nil,
          player_goals_type: "Int",
          player_goals_source: "goals",
          player_statline_dir: :in,
          player_statline_via: "playerId"
        )
          # `StatLine` is the source type, so its metadata carries the nested update targets we assert on.
          object_type_metadata_for "StatLine" do |s|
            if embed_players_under
              s.object_type s.state.type_ref(embed_players_under).fully_unwrapped.name do |t|
                t.field "players", players_field do |f|
                  f.mapping type: "object" if f.type.list?
                end
              end
            end

            s.object_type "Team" do |t|
              t.field "id", "ID!"

              if embed_players_under
                t.field "nested", embed_players_under do |f|
                  f.mapping type: "object" if f.type.list?
                end
              elsif players_field
                t.field "players", players_field do |f|
                  f.mapping type: "object" if f.type.list?
                end
              end

              t.relates_to_many "statLines", "StatLine", via: "teamId", dir: :in, indexing_only: true, &on_statlines_relationship
              on_team&.call(t)

              if index_teams
                t.index("teams") do |i|
                  i.has_had_multiple_sources! if multiple_sources
                  on_teams_index&.call(i)
                end
              end
            end

            s.object_type "Player" do |t|
              t.field "id", "ID!"

              t.field "goals", player_goals_type do |f|
                f.sourced_from "statLine", player_goals_source
              end

              t.relates_to_one "statLine", "StatLine", via: player_statline_via, dir: player_statline_dir, indexing_only: player_indexing_only do |r|
                on_player_relationship.call(r)
              end

              on_player&.call(t)

              if index_players
                t.index("players") { |i| i.has_had_multiple_sources! }
              end
            end

            s.object_type "StatLine" do |t|
              t.field "id", "ID!"
              t.field "teamId", "ID"
              t.field "playerId", "ID"
              t.field "goals", "Int"
              on_statline&.call(t)
              t.index "stat_lines"
            end

            yield s if block_given?
          end
        end

        def update_targets_for(
          type,
          widget_name: "String",
          widget_workspace_name: "String",
          widget_workspace_name_opts: {},
          widget_workspace_created_at: "DateTime",
          widget_workspace_nested_1_further_nested: "WidgetWorkspaceNested2",
          on_widgets_index: nil,
          on_widget_workspace_type: nil,
          index_widget_workspaces: true,
          type_name_overrides: {},
          &define_relation_and_sourced_from_fields
        )
          define_relation_and_sourced_from_fields ||= lambda do |t|
            t.relates_to_one "workspace", "WidgetWorkspace", via: "widget_ids", dir: :in

            t.field "workspace_name", "String" do |f|
              f.sourced_from "workspace", "name"
            end

            t.field "workspace_created_at", "DateTime" do |f|
              f.sourced_from "workspace", "created_at"
            end
          end

          metadata = object_type_metadata_for type, type_name_overrides: type_name_overrides do |s|
            s.enum_type "Color" do |t|
              t.value "RED"
              t.value "GREEN"
              t.value "BLUE"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", widget_name

              define_relation_and_sourced_from_fields.call(t)

              t.index "widgets" do |index|
                index.has_had_multiple_sources! if t.fields_with_sources.any?
                on_widgets_index&.call(index)
              end
            end

            s.object_type "WidgetWorkspaceNested1" do |t|
              t.field "further_nested", widget_workspace_nested_1_further_nested, name_in_index: "further_nested_in_index" do |f|
                f.mapping type: "object" if widget_workspace_nested_1_further_nested.include?("[")
              end
              t.field "owner_id", "ID!"
              t.field "timestamp", "DateTime"
            end

            s.object_type "WidgetWorkspaceNested2" do |t|
              t.field "name", "String"
            end

            s.object_type "WidgetWorkspace" do |t|
              t.field "id", "ID!"
              t.field "workspace_owner_id", "ID!"
              t.field "name", widget_workspace_name, **widget_workspace_name_opts
              t.field "created_at", widget_workspace_created_at
              t.field "workspace_created_at", widget_workspace_created_at
              t.field "nested", "WidgetWorkspaceNested1"
              t.relates_to_many "widgets", "Widget", via: "widget_ids", dir: :out, singular: "widget"

              on_widget_workspace_type&.call(t)

              t.index "widget_workspaces" if index_widget_workspaces
            end
          end

          metadata.update_targets
        end
      end

      context "on a normal indexed type" do
        it "dumps information about update targets" do
          metadata = object_type_metadata_for "Widget" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "workspace_id", "ID!"
              t.field "name", "String!"
              t.index "widgets"
              t.derive_indexed_type_fields "WidgetWorkspace", from_id: "workspace_id" do |derive|
                derive.append_only_set "widget_ids", from: "id"
              end
            end

            s.object_type "WidgetWorkspace" do |t|
              t.field "id", "ID!"
              t.index "widget_workspaces"
            end
          end

          expect(metadata.update_targets.map(&:type)).to contain_exactly("WidgetWorkspace", "Widget")

          widget_workspace_target = metadata.update_targets.find { |t| t.type == "WidgetWorkspace" }
          expect(widget_workspace_target.type).to eq "WidgetWorkspace"
          expect(widget_workspace_target.relationship).to eq nil
          expect(widget_workspace_target.script_id).to start_with "update_WidgetWorkspace_from_Widget_"
          expect(widget_workspace_target.id_source).to eq "workspace_id"
          expect(widget_workspace_target.routing_value_source).to eq(nil)
          expect(widget_workspace_target.rollover_timestamp_value_source).to eq(nil)
          expect(widget_workspace_target.top_level_fields_params).to eq({"id" => dynamic_param_with(source_path: "id", cardinality: :many)})
          expect(widget_workspace_target.metadata_params).to eq({})

          widget_target = metadata.update_targets.find { |t| t.type == "Widget" }
          expect(widget_target.type).to eq "Widget"
          expect(widget_target.relationship).to eq SELF_RELATIONSHIP_NAME
          expect(widget_target.script_id).to eq(INDEX_DATA_UPDATE_SCRIPT_ID)
          expect(widget_target.id_source).to eq "id"
          expect(widget_target.routing_value_source).to eq("id")
          expect(widget_target.rollover_timestamp_value_source).to eq(nil)
          expect(widget_target.top_level_fields_params).to eq({
            "name" => dynamic_param_with(source_path: "name", cardinality: :one),
            "workspace_id" => dynamic_param_with(source_path: "workspace_id", cardinality: :one)
          })
          expect(widget_target.metadata_params).to eq(standard_metadata_params(relationship: SELF_RELATIONSHIP_NAME))
        end

        it "respects a type name override for the destination type" do
          metadata = object_type_metadata_for("Widget", type_name_overrides: {WidgetWorkspace: "WorkspaceOfWidget"}) do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "workspace_id", "ID!"
              t.field "name", "String!"
              t.index "widgets"
              t.derive_indexed_type_fields "WidgetWorkspace", from_id: "workspace_id" do |derive|
                derive.append_only_set "widget_ids", from: "id"
              end
            end

            s.object_type "WidgetWorkspace" do |t|
              t.field "id", "ID!"
              t.index "widget_workspaces"
            end
          end

          expect(metadata.update_targets.map(&:type)).to contain_exactly("WorkspaceOfWidget", "Widget")
        end

        it "dumps only the 'self' update target when the indexed type has no derived indexing types" do
          metadata = object_type_metadata_for "Widget" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "cost", "Int"
              t.index "widgets"
            end
          end

          expect(metadata.update_targets.map(&:type)).to contain_exactly("Widget")

          widget_target = metadata.update_targets.find { |t| t.type == "Widget" }
          expect(widget_target.type).to eq "Widget"
          expect(widget_target.relationship).to eq SELF_RELATIONSHIP_NAME
          expect(widget_target.script_id).to eq(INDEX_DATA_UPDATE_SCRIPT_ID)
          expect(widget_target.id_source).to eq "id"
          expect(widget_target.routing_value_source).to eq("id")
          expect(widget_target.rollover_timestamp_value_source).to eq(nil)
          expect(widget_target.top_level_fields_params).to eq({"cost" => dynamic_param_with(source_path: "cost", cardinality: :one)})
          expect(widget_target.metadata_params).to eq(standard_metadata_params(relationship: SELF_RELATIONSHIP_NAME))
        end

        it "sets the `routing_value_source` correctly when the index uses custom shard routing" do
          metadata = object_type_metadata_for "Widget" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "workspace_id", "ID"
              t.index "widgets" do |i|
                i.route_with "workspace_id"
              end
            end
          end

          expect(metadata.update_targets.map(&:type)).to contain_exactly("Widget")

          widget_target = metadata.update_targets.find { |t| t.type == "Widget" }
          expect(widget_target.routing_value_source).to eq("workspace_id")
        end

        it "sets the `rollover_timestamp_value_source` correctly when the index uses rollover indexes" do
          metadata = object_type_metadata_for "Widget" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "created_at", "DateTime"
              t.index "widgets" do |i|
                i.rollover :monthly, "created_at"
              end
            end
          end

          expect(metadata.update_targets.map(&:type)).to contain_exactly("Widget")

          widget_target = metadata.update_targets.find { |t| t.type == "Widget" }
          expect(widget_target.rollover_timestamp_value_source).to eq("created_at")
        end
      end

      context "on an embedded object type" do
        it "dumps no `update_targets`" do
          metadata = object_type_metadata_for "WidgetOptions" do |s|
            s.object_type "WidgetOptions" do |t|
              t.field "size", "Int", name_in_index: "size_index"
            end
          end

          expect(metadata.update_targets).to be_empty
        end
      end

      on_a_type_union_or_interface_type do |type_def_method|
        it "does not dump information about `update_targets` based on the subtypes; that info will be dumped on those types" do
          metadata = object_type_metadata_for "Thing" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              # Use an alternate `name_in_index` to force `metadata` not to be `nil`.
              t.field "workspace_id", "ID!", name_in_index: "wid"
              t.index "widgets"
              link_subtype_to_supertype(t, "Thing")
              t.derive_indexed_type_fields "WidgetWorkspace", from_id: "workspace_id" do |derive|
                derive.append_only_set "widget_ids", from: "id"
              end
            end

            s.object_type "WidgetWorkspace" do |t|
              t.field "id", "ID!"
              t.index "widget_workspaces"
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

          expect(metadata.update_targets).to eq []
        end

        it "dumps info about `update_targets` from the supertype itself" do
          metadata = object_type_metadata_for "Thing" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "workspace_id", "ID!"
              link_subtype_to_supertype(t, "Thing")
              t.index "widgets"
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.field "workspace_id", "ID!"
              link_subtype_to_supertype(t, "Thing")
              t.index "components"
            end

            s.public_send type_def_method, "Thing" do |t|
              link_supertype_to_subtypes(t, "Widget", "Component")
              t.index "things"
              t.derive_indexed_type_fields "ThingWorkspace", from_id: "workspace_id" do |derive|
                derive.append_only_set "thing_ids", from: "id"
              end
            end

            s.object_type "ThingWorkspace" do |t|
              t.field "id", "ID!"
              t.index "thing_workspaces"
            end
          end

          expect(metadata.update_targets.size).to eq 1
          expect(metadata.update_targets.first.type).to eq "ThingWorkspace"
          expect(metadata.update_targets.first.relationship).to eq nil
          expect(metadata.update_targets.first.script_id).to start_with "update_ThingWorkspace_from_Thing"
          expect(metadata.update_targets.first.id_source).to eq "workspace_id"
          expect(metadata.update_targets.first.top_level_fields_params).to eq({"id" => dynamic_param_with(source_path: "id", cardinality: :many)})
          expect(metadata.update_targets.first.metadata_params).to eq({})
        end

        it "inherits routing configuration from the parent abstract type's index when the concrete type has no direct index" do
          widget_metadata, component_metadata = object_type_metadata_for("Widget", "Component") do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "workspace_id", "ID!"
              link_subtype_to_supertype(t, "Thing")
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.field "workspace_id", "ID!"
              link_subtype_to_supertype(t, "Thing")
            end

            s.public_send type_def_method, "Thing" do |t|
              link_supertype_to_subtypes(t, "Widget", "Component")
              t.index "things" do |i|
                i.route_with "workspace_id"
              end
            end
          end

          widget_target = widget_metadata.update_targets.find { |t| t.type == "Widget" }
          expect(widget_target.routing_value_source).to eq("workspace_id")

          component_target = component_metadata.update_targets.find { |t| t.type == "Component" }
          expect(component_target.routing_value_source).to eq("workspace_id")
        end

        it "inherits rollover configuration from the parent abstract type's index when the concrete type has no direct index" do
          widget_metadata, component_metadata = object_type_metadata_for("Widget", "Component") do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "created_at", "DateTime!"
              link_subtype_to_supertype(t, "Thing")
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.field "created_at", "DateTime!"
              link_subtype_to_supertype(t, "Thing")
            end

            s.public_send type_def_method, "Thing" do |t|
              link_supertype_to_subtypes(t, "Widget", "Component")
              t.index "things" do |i|
                i.rollover :monthly, "created_at"
              end
            end
          end

          widget_target = widget_metadata.update_targets.find { |t| t.type == "Widget" }
          expect(widget_target.rollover_timestamp_value_source).to eq("created_at")

          component_target = component_metadata.update_targets.find { |t| t.type == "Component" }
          expect(component_target.rollover_timestamp_value_source).to eq("created_at")
        end

        it "defaults to standard routing when the parent abstract type's index has no custom routing or rollover configuration" do
          widget_metadata = object_type_metadata_for("Widget") do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              link_subtype_to_supertype(t, "Thing")
            end

            s.public_send type_def_method, "Thing" do |t|
              link_supertype_to_subtypes(t, "Widget")
              t.index "things"
            end
          end

          widget_target = widget_metadata.update_targets.find { |t| t.type == "Widget" }
          expect(widget_target.routing_value_source).to eq("id") # defaults to id when no custom routing
          expect(widget_target.rollover_timestamp_value_source).to be_nil # no default for rollover
        end

        it "includes __typename in top_level_fields_params for types that inherit an index (needed for field extraction during indexing)" do
          widget_metadata, component_metadata = object_type_metadata_for("Widget", "Component") do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              link_subtype_to_supertype(t, "Thing")
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.field "size", "Int"
              link_subtype_to_supertype(t, "Thing")
            end

            s.public_send type_def_method, "Thing" do |t|
              link_supertype_to_subtypes(t, "Widget", "Component")
              t.index "things"
            end
          end

          widget_target = widget_metadata.update_targets.find { |t| t.type == "Widget" }
          expect(widget_target.top_level_fields_params.keys).to include("__typename")
          expect(widget_target.top_level_fields_params["__typename"].source_path).to eq "__typename"

          component_target = component_metadata.update_targets.find { |t| t.type == "Component" }
          expect(component_target.top_level_fields_params.keys).to include("__typename")
          expect(component_target.top_level_fields_params["__typename"].source_path).to eq "__typename"
        end
      end

      def standard_metadata_params(relationship:)
        {"sourceId" => "id", "sourceType" => "type", "version" => "version"}.transform_values do |source_path|
          dynamic_param_with(source_path: source_path, cardinality: :one)
        end.merge({
          "relationship" => static_param_with(relationship)
        })
      end
    end
  end
end
