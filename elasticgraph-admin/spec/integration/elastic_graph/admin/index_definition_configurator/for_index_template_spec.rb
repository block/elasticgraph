# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "shared_examples"
require "elastic_graph/schema_definition/schema_artifact_manager"

module ElasticGraph
  class Admin
    module IndexDefinitionConfigurator
      RSpec.describe ForIndexTemplate do
        include_examples IndexDefinitionConfigurator do
          def concrete_index_name_for_now(base_index_name)
            "#{base_index_name}_rollover__2024-03" # clock.now is at a time on 2024-03-20
          end

          prepend Module.new {
            def schema_def(**options)
              configure_index = ->(index) { index.rollover :monthly, "created_at" }
              super(configure_index: configure_index, **options)
            end
          }

          def get_index_definition_configuration(index_definition_name)
            index_template = main_datastore_client.get_index_template(index_definition_name)
            expect(index_template).to include("index_patterns" => ["#{index_definition_name}_rollover__*"]).or be_empty
            index_template["template"] || {}
          end
          alias_method :get_index_template_definition_configuration, :get_index_definition_configuration

          # Index templates don't have separate _settings or _mappings subresources, so we ignore it here.
          def put_index_definition_url(index_definition_name, _subresource = nil)
            "/_index_template/#{index_definition_name}"
          end
          alias_method :put_index_template_definition_url, :put_index_definition_url

          def make_datastore_calls_to_configure_index_def(index_name, subresource = nil)
            # :nocov: -- when we are building against OpenSearch, one side of this conditional is not covered
            subresource = :mapping if subresource == :mappings && datastore_backend == :elasticsearch
            # :nocov:

            path_for_now_index = "/#{concrete_index_name_for_now(index_name)}"
            path_for_now_index += "/_#{subresource}" if subresource

            make_datastore_write_calls(
              "main",
              "PUT #{put_index_definition_url(index_name, subresource)}",
              "PUT #{path_for_now_index}"
            )
          end

          def simulate_presence_of_extra_setting(admin, index_definition_name, name, value)
            admin.datastore_core.clients_by_name.values.each do |client|
              allow(client).to receive(:get_index_template).with(index_definition_name).and_wrap_original do |original, *args, **kwargs, &block|
                original.call(*args, **kwargs, &block).tap do |result|
                  # Mutate the settings before we return them.
                  result["template"]["settings"][name] = value
                end
              end
            end
          end

          def fetch_artifact_configuration(schema_artifacts, index_def_name)
            schema_artifacts.index_templates.fetch(index_def_name)
          end

          # Allow index templates to change static index settings such as `index.number_of_shards` because the datastore allows it.
          # Could also be beneficial for us if we need more shards as the data grows big for the new indices of a rollover index
          it "allows changes to static index settings on an index template since the datastore allows it and it could be useful" do
            configure_index_definition(schema_def(number_of_shards: 10))

            expect {
              configure_index_definition(schema_def) do |config|
                config.with(index_definitions: {
                  "#{unique_index_name}_owners" => config_index_def_of,
                  unique_index_name => config_index_def_of(
                    setting_overrides: {"number_of_shards" => 47},
                    setting_overrides_by_timestamp: {
                      clock.now.getutc.iso8601 => {"number_of_shards" => 10}
                    }
                  )
                })
              end
            }.to change { get_index_definition_configuration(unique_index_name).fetch("settings") }
              .from(a_hash_including("index.number_of_shards" => "10"))
              .to(a_hash_including("index.number_of_shards" => "47"))
              .and make_datastore_calls_to_configure_index_def(unique_index_name, :settings)
          end

          it "creates concrete indices based on `setting_overrides_by_timestamp` configuration, and avoids creating an extra index for 'now'" do
            jan_2020_index_name = unique_index_name + "_rollover__2020-01"

            expect {
              configure_index_definition(schema_def(number_of_shards: 5)) do |config|
                config.with(index_definitions: {
                  "#{unique_index_name}_owners" => config_index_def_of,
                  unique_index_name => config_index_def_of(setting_overrides_by_timestamp: {
                    "2020-01-01T00:00:00Z" => {
                      "number_of_shards" => 3
                    }
                  })
                })
              end
            }.to change { get_index_definition_configuration(unique_index_name)["settings"] }
              .from(nil)
              .to(a_hash_including("index.number_of_shards" => "5"))
              .and change { main_datastore_client.get_index(jan_2020_index_name)["settings"] }
              .from(nil)
              .to(a_hash_including("index.number_of_shards" => "3"))
              .and maintain { main_datastore_client.get_index(concrete_index_name_for_now(unique_index_name))["settings"] }
              .from(nil)

            index_def_creation_order = datastore_write_requests("main").filter_map { |r| r.url.path.split("/").last if r.http_method == :put }
            # the specific jan_2020 index must be created before the index template to guard against
            # the jan_2020 index being generated from the template by another process concurrently indexing
            # a jan 2020 document.
            expect(index_def_creation_order).to eq([jan_2020_index_name, unique_index_name])
          end

          context "when the settings do not force the creation of any concrete indices" do
            it "creates an index using the current time so that our search queries always have an index to hit" do
              expect {
                configure_index_definition(schema_def)
              }.to change { get_index_definition_configuration(unique_index_name) }
                .from({})
                .to(a_hash_including("mappings", "settings"))
                .and change { main_datastore_client.get_index(concrete_index_name_for_now(unique_index_name)) }
                .from({})
                .to(a_hash_including("mappings", "settings"))
            end
          end

          context "when a concrete index has been derived from the template", :factories do
            include ConcreteIndexAdapter

            # our schema in the tests here is more limited than the main widget schema, so select only some fields.
            let(:widget) { build(:widget).select { |k, v| k.start_with?("__") || %i[id name options created_at].include?(k) } }

            let(:concrete_index_name) do
              admin_for(schema_def)
                .datastore_core
                .index_definitions_by_name
                .fetch(unique_index_name)
                .index_name_for_writes(Support::HashUtil.stringify_keys(widget))
            end

            it "propagates mapping changes to the derived concrete rollover indices, ignoring the fact that the derived indices are not in the dumped schema artifacts", :in_temp_dir do
              configure_index_definition(schema_def)
              index_into(indexer_for(schema_def), widget)

              updated_schema = schema_def(configure_widget: ->(t) { t.field "amount_cents", "Int" })

              SchemaDefinition::SchemaArtifactManager.new(
                schema_definition_results: generate_schema_artifacts(&updated_schema),
                schema_artifacts_directory: Dir.pwd,
                enforce_json_schema_version: true,
                output: output_io
              ).dump_artifacts

              expect {
                configure_index_definition(updated_schema, schema_artifacts_directory: Dir.pwd)
              }.to change { get_index_definition_configuration(concrete_index_name).dig("mappings", "properties").keys.sort }
                .from([*index_meta_fields, "created_at", "id", "name", "options"])
                .to([*index_meta_fields, "amount_cents", "created_at", "id", "name", "options"])
                .and make_datastore_write_calls("main",
                  "PUT #{put_index_template_definition_url(unique_index_name)}",
                  "PUT #{put_index_definition_url(concrete_index_name_for_now(unique_index_name), :mappings)}",
                  "PUT #{put_index_definition_url(concrete_index_name, :mappings)}")
            end

            it "propagates setting changes to the derived concrete rollover indices" do
              configure_index_definition(schema_def)
              index_into(indexer_for(schema_def), widget)

              expect {
                configure_index_definition(schema_def(refresh_interval: "5s"))
              }.to change { get_index_definition_configuration(concrete_index_name).fetch("settings").keys }
                .from(a_collection_excluding("index.refresh_interval"))
                .to(a_collection_including("index.refresh_interval"))
                .and make_datastore_write_calls("main",
                  "PUT #{put_index_template_definition_url(unique_index_name)}",
                  "PUT #{put_index_definition_url(concrete_index_name_for_now(unique_index_name), :settings)}",
                  "PUT #{put_index_definition_url(concrete_index_name, :settings)}")
            end

            it "fails before any changes are made if the changes can't be propagated to the concrete rollover indices" do
              configure_index_definition(schema_def)
              index_into(indexer_for(schema_def), widget)

              main_datastore_client.put_index_mapping(index: concrete_index_name, body: {
                properties: {
                  amount_cents: {type: "keyword"}
                }
              })

              expect {
                configure_index_definition(schema_def(configure_widget: ->(t) { t.field "amount_cents", "Int" }))
              }.to maintain { get_index_definition_configuration(concrete_index_name) }
                .and maintain { get_index_template_definition_configuration(unique_index_name) }
                .and raise_error(Errors::IndexOperationError, a_string_including(concrete_index_name, "properties.amount_cents.type"))
            end

            def indexer_for(schema_def)
              build_indexer(schema_definition: schema_def)
            end
          end
        end
      end
    end
  end
end
