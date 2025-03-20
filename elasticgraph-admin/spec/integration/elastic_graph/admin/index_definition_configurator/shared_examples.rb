# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin/index_definition_configurator"
require "elastic_graph/errors"
require "stringio"

module ElasticGraph
  class Admin
    module IndexDefinitionConfigurator
      module ConcreteIndexAdapter
        def get_index_definition_configuration(index_definition_name)
          main_datastore_client.get_index(index_definition_name)
        end

        def put_index_definition_url(index_definition_name, subresource = nil)
          url = "/#{index_definition_name}"
          # :nocov: -- when we are building against OpenSearch, one side of this conditional is not covered
          subresource = :mapping if subresource == :mappings && datastore_backend == :elasticsearch
          # :nocov:
          subresource ? "#{url}/_#{subresource}" : url
        end

        def simulate_presence_of_extra_setting(admin, index_definition_name, name, value)
          admin.datastore_core.clients_by_name.values.each do |client|
            allow(client).to receive(:get_index).with(index_definition_name).and_wrap_original do |original, *args, **kwargs, &block|
              original.call(*args, **kwargs, &block).tap do |result|
                # Mutate the settings before we return them.
                result.fetch("settings")[name] = value
              end
            end
          end
        end
      end

      RSpec.shared_examples_for IndexDefinitionConfigurator, :uses_datastore, :builds_indexer do
        let(:output_io) { StringIO.new }
        let(:clock) { class_double(::Time, now: ::Time.utc(2024, 3, 20, 12, 0, 0)) }
        let(:mapping_removal_note_snippet) { "extra fields listed here will not actually get removed" }
        let(:index_meta_fields) { ["__sources", "__versions"] }

        it "idempotently creates an index or index template, avoiding unneeded datastore write calls" do
          expect {
            configure_index_definition(schema_def)
          }.to change { get_index_definition_configuration(unique_index_name) }
            .from({})
            .to(a_hash_including(
              "mappings" => a_hash_including("properties" => a_hash_including("id", "name", "options", "created_at")),
              "settings" => a_kind_of(Hash)
            ))
            .and make_datastore_calls_to_configure_index_def(unique_index_name)

          expect {
            configure_index_definition(schema_def)
          }.to maintain { get_index_definition_configuration(unique_index_name) }
            .and make_no_datastore_write_calls("main")

          expect(output_io.string).not_to include(mapping_removal_note_snippet)
        end

        it "allows new top-level fields to be added to an existing index or index template" do
          configure_index_definition(schema_def)
          output_io.string = +"" # use `+` so it is not a frozen string literal.

          expect {
            configure_index_definition(schema_def(configure_widget: ->(t) { t.field "amount_cents", "Int" }))
          }.to change { get_index_definition_configuration(unique_index_name).dig("mappings", "properties").keys.sort }
            .from([*index_meta_fields, "created_at", "id", "name", "options"])
            .to([*index_meta_fields, "amount_cents", "created_at", "id", "name", "options"])
            .and make_datastore_calls_to_configure_index_def(unique_index_name, :mappings)

          # The printed description of what was changed should not mention settings that are not being updated.
          # (Requires us to normalize settings properly in the logic for this to be the case).
          expect(output_io.string).to include("properties.amount_cents").and exclude("coerce", "ignore_malformed", "number_of_replicas", "number_of_shards")
          expect(output_io.string).not_to include(mapping_removal_note_snippet)
        end

        it "handles both `object` lists and `nested` lists" do
          schema_def = schema_def(configure_widget: ->(t) {
            t.field "object_list", "[WidgetOptions!]!" do |f|
              f.mapping type: "object"
            end

            t.field "nested_list", "[WidgetOptions!]!" do |f|
              f.mapping type: "nested"
            end
          })

          expect {
            configure_index_definition(schema_def)
          }.to change { get_index_definition_configuration(unique_index_name) }
            .from({})
            .to(a_hash_including("mappings" => a_hash_including("properties" => a_hash_including("object_list", "nested_list"))))
            .and make_datastore_calls_to_configure_index_def(unique_index_name)

          expect {
            configure_index_definition(schema_def)
          }.to maintain { get_index_definition_configuration(unique_index_name) }
            .and make_no_datastore_write_calls("main")
        end

        it "allows new fields on an embedded object to be added to an existing index or index template" do
          configure_index_definition(schema_def)

          expect {
            configure_index_definition(schema_def(configure_widget_options: ->(t) { t.field "weight", "Int" }))
          }.to change { get_index_definition_configuration(unique_index_name).dig("mappings", "properties", "options", "properties").keys.sort }
            .from(["color", "size"])
            .to(["color", "size", "weight"])
            .and make_datastore_calls_to_configure_index_def(unique_index_name, :mappings)
        end

        it "does not support changing a field's mapping type on an existing index (since the datastore does not support it) or from an existing index template (for behavior consistency)" do
          configure_index_definition(schema_def)

          expect {
            configure_index_definition(schema_def(
              avoid_defining_widget_fields: %w[name],
              configure_widget: ->(t) { t.field "name", "Int" }
            ))
          }.to raise_error(Errors::IndexOperationError, /name/)
        end

        it "supports adding a dynamic mapping param on an existing field on an existing index or index template" do
          configure_index_definition(schema_def)

          expect {
            configure_index_definition(schema_def(
              avoid_defining_widget_fields: %w[name],
              configure_widget: ->(t) {
                t.field "name", "String" do |f|
                  f.mapping meta: {foo: "1"}
                end
              }
            ))
          }.to change { get_index_definition_configuration(unique_index_name).dig("mappings", "properties", "name") }
            .from({"type" => "keyword"})
            .to({"type" => "keyword", "meta" => {"foo" => "1"}})
            .and make_datastore_calls_to_configure_index_def(unique_index_name, :mappings)
        end

        it "supports removing a dynamic mapping param on an existing field on an existing index or index template" do
          configure_index_definition(schema_def(
            avoid_defining_widget_fields: %w[name],
            configure_widget: ->(t) {
              t.field "name", "String" do |f|
                f.mapping meta: {foo: "1"}
              end
            }
          ))

          expect {
            configure_index_definition(schema_def)
          }.to change { get_index_definition_configuration(unique_index_name).dig("mappings", "properties", "name") }
            .from({"type" => "keyword", "meta" => {"foo" => "1"}})
            .to({"type" => "keyword"})
            .and make_datastore_calls_to_configure_index_def(unique_index_name, :mappings)
        end

        it "allows some previously unset settings to be changed on an existing index or index template" do
          configure_index_definition(schema_def)

          expect {
            configure_index_definition(schema_def(refresh_interval: "5s"))
          }.to change { get_index_definition_configuration(unique_index_name).fetch("settings").keys }
            .from(a_collection_excluding("index.refresh_interval"))
            .to(a_collection_including("index.refresh_interval"))
            .and make_datastore_calls_to_configure_index_def(unique_index_name, :settings)
        end

        it "allows some previously set index or index template settings to be restored to defaults" do
          configure_index_definition(schema_def(refresh_interval: "5s"))
          output_io.string = +"" # use `+` so it is not a frozen string literal.

          expect {
            configure_index_definition(schema_def)
          }.to change { get_index_definition_configuration(unique_index_name).fetch("settings") }
            .from(a_collection_including("index.refresh_interval"))
            .to(a_collection_excluding("index.refresh_interval"))
            .and make_datastore_calls_to_configure_index_def(unique_index_name, :settings)

          # The printed description of what was changed should not mention settings that are not being updated.
          # (Requires us to normalize settings properly in the logic for this to be the case).
          expect(output_io.string).to include("index.refresh_interval").and exclude("coerce", "ignore_malformed", "number_of_replicas", "number_of_shards")
        end

        it "ignores the `index.version.upgraded` read-only index or index template setting that can apparently be returned by `indices.get` on an upgraded cluster" do
          configure_index_definition(schema_def)

          expect {
            configure_index_definition(schema_def, customize_admin: lambda do |admin|
              # Add in the weird index setting we are seeing on AWS but cannot find any documentation about
              # what it means and when it is present. It appears to be related to upgrading a cluster, which
              # is hard to setup in our tests, so we adding it in here.
              simulate_presence_of_extra_setting(admin, unique_index_name, "index.version.upgraded", "7070099")
            end)
          }.to make_no_datastore_write_calls("main")
        end

        it "is a no-op when we attempt to drop a field because the datastore doesn't support dropping mapping fields" do
          configure_index_definition(schema_def)

          expect {
            # Here we remove the `name` field and the `options.size` field to verify it works for both root and nested fields.
            configure_index_definition(schema_def(
              avoid_defining_widget_fields: %w[name],
              avoid_defining_widget_options_fields: %w[size]
            ))
          }.to maintain {
            props = get_index_definition_configuration(unique_index_name).dig("mappings", "properties")
            [props.keys.sort, props.dig("options", "properties").keys.sort]
          }.from([[*index_meta_fields, "created_at", "id", "name", "options"], ["color", "size"]])
            .and make_datastore_calls_to_configure_index_def(unique_index_name, :mappings)

          expect(output_io.string).to include(mapping_removal_note_snippet)
        end

        it "maintains `_meta.ElasticGraph.sources` as a stateful append-only-set that remembers sources that were once active but we no longer have" do
          expect {
            configure_index_definition(schema_def(
              configure_widget: lambda do |t|
                t.relates_to_one "owner", "WidgetOwner", via: "widget_ids", dir: :in do |rel|
                  rel.equivalent_field "created_at"
                end

                t.field "owner_name", "String" do |f|
                  f.sourced_from "owner", "name"
                end
              end
            ))
          }.to change { get_index_definition_configuration(unique_index_name).dig("mappings", "_meta") }
            .from(nil)
            .to({"ElasticGraph" => {"sources" => ["__self", "owner"]}})

          expect {
            configure_index_definition(schema_def(
              configure_widget: lambda do |t|
                t.relates_to_one "owner2", "WidgetOwner", via: "widget_ids", dir: :in do |rel|
                  rel.equivalent_field "created_at"
                end

                t.field "owner_name", "String" do |f|
                  f.sourced_from "owner2", "name"
                end
              end
            ))
          }.to change { get_index_definition_configuration(unique_index_name).dig("mappings", "_meta") }
            .from({"ElasticGraph" => {"sources" => ["__self", "owner"]}})
            .to({"ElasticGraph" => {"sources" => ["__self", "owner", "owner2"]}})
        end

        it "allows index sorting to be configured so long as there are no fields using the `nested` mapping type" do
          expect {
            configure_index_definition(schema_def(sort: {field: ["created_at"], order: ["asc"]}))
          }.to change {
            settings = get_index_definition_configuration(unique_index_name)["settings"] || {}
            [settings["index.sort.field"], settings["index.sort.order"]]
          }.from([nil, nil]).to([["created_at"], ["asc"]])
        end

        def schema_def(
          configure_index: nil,
          configure_widget: nil,
          configure_widget_options: nil,
          avoid_defining_widget_fields: [],
          avoid_defining_widget_options_fields: [],
          define_no_widget_fields: false,
          **index_settings
        )
          define_widget_field = lambda do |t, name, type|
            return if avoid_defining_widget_fields.include?(name)
            return if define_no_widget_fields
            t.field name, type
          end

          define_widget_options_field = lambda do |t, name, type|
            return if avoid_defining_widget_options_fields.include?(name)
            t.field name, type
          end

          lambda do |schema|
            schema.object_type "WidgetOwner" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "widget_ids", "[ID!]!"
              t.field "created_at", "DateTime"
              t.index "#{unique_index_name}_owners"
            end

            schema.object_type "WidgetOptions" do |t|
              define_widget_options_field.call(t, "size", "String")
              define_widget_options_field.call(t, "color", "String")

              configure_widget_options&.call(t)
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID!" # can't be omitted.

              define_widget_field.call(t, "name", "String")
              define_widget_field.call(t, "options", "WidgetOptions")
              define_widget_field.call(t, "created_at", "DateTime!")

              configure_widget&.call(t)

              t.index unique_index_name, **index_settings, &configure_index
            end
          end
        end

        def configure_index_definition(schema_def, schema_artifacts_directory: nil, customize_admin: nil, &customize_datastore_config)
          admin = admin_for(schema_def, schema_artifacts_directory: schema_artifacts_directory, &customize_datastore_config)
          configure_index_def_using_admin(admin, &customize_admin)
        end

        def configure_index_def_using_admin(admin, try_dry_run: true, &customize_admin)
          if try_dry_run
            # To relieve us of the need of having to write manual test coverage for each possible configuration
            # action, to verify that it's `dry_run` mode works correctly, here we test it automatically.
            # Before performing the action with the normal datastore client, we first try it with the dry
            # run client to prove that it makes no write calls to the datastore.
            expect do
              configure_index_def_using_admin(admin.with_dry_run_datastore_clients, try_dry_run: false, &customize_admin)
            rescue Errors::IndexOperationError
              # some tests trigger this intentionally; ignore it if so
            end.to make_no_datastore_write_calls("main")
          end

          customize_admin&.call(admin)

          index_definition = admin.datastore_core.index_definitions_by_name.fetch(unique_index_name)
          artifact_configuration = fetch_artifact_configuration(admin.datastore_core.schema_artifacts, index_definition.name)

          configurator = IndexDefinitionConfigurator.new(
            # Note: this MUST use a datastore client off the application so that a dry-run client is used
            # when needed, rather than using `main_datastore_client` (provided by the `:uses_datastore` tag), which
            # will not be a dry-run client ever.
            admin.datastore_core.clients_by_name.fetch("main"),
            index_definition,
            artifact_configuration,
            output_io,
            clock
          )

          if (errors = configurator.validate).any?
            raise Errors::IndexOperationError, errors.join("; ")
          end

          configurator.configure!
        end

        def admin_for(schema_def, **options, &customize_datastore_config)
          build_admin(schema_definition: schema_def, **options, &customize_datastore_config)
        end
      end
    end
  end
end
