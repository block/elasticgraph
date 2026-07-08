# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "shared_examples"

module ElasticGraph
  class Admin
    module IndexDefinitionConfigurator
      RSpec.describe ForIndex do
        include_examples IndexDefinitionConfigurator do
          include ConcreteIndexAdapter

          it "raises an exception when attempting to change a static index setting (since the datastore disallows it)" do
            configure_index_definition(schema_def)

            expect {
              configure_index_definition(schema_def(number_of_shards: 47))
            }.to raise_error(Errors::BadDatastoreRequest, a_string_including("Can't update non dynamic setting", "index.number_of_shards"))
              .and make_datastore_write_calls("main", "PUT /#{unique_index_name}/_settings")
              .and log_warning(/Can't update non dynamic setting/)
          end

          it "handles empty indexed types" do
            schema = schema_def(define_no_widget_fields: true)

            configure_index_definition(schema)

            expect {
              configure_index_definition(schema)
            }.to make_no_datastore_write_calls("main")
          end

          # Note: this behavior differs from index templates (see `for_index_template_spec.rb`): the datastore
          # allows template fields to be dropped, but provides no way to remove fields from a concrete index.
          it "is a no-op when attempting to drop a mapping field because the datastore does not support it" do
            configure_index_definition(schema_def)
            output_io.string = +"" # use `+` so it is not a frozen string literal.

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
              .and make_no_datastore_write_calls("main")

            expect(output_io.string).to exclude("Updated mappings", "properties.name", "properties.options.properties.size")
          end

          def make_datastore_calls_to_configure_index_def(index_name, subresource = nil)
            make_datastore_write_calls("main", "PUT #{put_index_definition_url(index_name, subresource)}")
          end

          def fetch_artifact_configuration(schema_artifacts, index_def_name)
            schema_artifacts.indices.fetch(index_def_name)
          end
        end
      end
    end
  end
end
