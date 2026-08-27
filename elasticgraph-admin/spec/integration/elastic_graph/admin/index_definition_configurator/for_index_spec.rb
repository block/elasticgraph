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

          it "applies mapping updates before alias updates so that an alias filter can reference a newly declared field" do
            nested_alias = "#{unique_index_name}_nested"
            # The datastore rejects a `nested` alias filter when the path is not yet in the index mapping.
            nested_filter = {"nested" => {"path" => "nested_options", "query" => {"term" => {"nested_options.size" => "large"}}}}

            configure_index_definition(schema_def)

            expect {
              configure_index_definition(schema_def(
                configure_widget: ->(t) {
                  t.field "nested_options", "[WidgetOptions!]!" do |f|
                    f.mapping type: "nested"
                  end
                },
                configure_index: ->(index) {
                  index.customize_config do |config|
                    config["aliases"] = {nested_alias => {"filter" => nested_filter}}
                  end
                }
              ))
            }.to change { aliases_of(unique_index_name) }
              .from({})
              .to({nested_alias => {"filter" => nested_filter}})
          end

          it "handles empty indexed types" do
            schema = schema_def(define_no_widget_fields: true)

            configure_index_definition(schema)

            expect {
              configure_index_definition(schema)
            }.to make_no_datastore_write_calls("main")
          end

          def make_datastore_calls_to_configure_index_def(index_name, subresource = nil)
            make_datastore_write_calls("main", "PUT #{put_index_definition_url(index_name, subresource)}")
          end

          def make_datastore_calls_to_update_aliases(_index_name)
            make_datastore_write_calls("main", "POST /_aliases")
          end

          def fetch_artifact_configuration(schema_artifacts, index_def_name)
            schema_artifacts.indices.fetch(index_def_name)
          end
        end
      end
    end
  end
end
