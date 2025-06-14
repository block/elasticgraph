# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql"

module ElasticGraph
  RSpec.describe GraphQL do
    it "returns non-nil values from each attribute" do
      expect_to_return_non_nil_values_from_all_attributes(build_graphql)
    end

    describe ".from_parsed_yaml" do
      it "builds a GraphQL instance from the contents of a YAML settings file" do
        customization_block = lambda { |conn| }
        graphql = GraphQL.from_parsed_yaml(parsed_test_settings_yaml, &customization_block)

        expect(graphql).to be_a(GraphQL)
        expect(graphql.datastore_core.client_customization_block).to be(customization_block)
      end
    end

    describe "#schema" do
      it "fails to load if the resolver for any fields cannot be found" do
        graphql = build_graphql(
          extension_modules: [Module.new {
            def named_graphql_resolvers
              super.except(:get_record_field_value)
            end
          }],
          schema_definition: ->(schema) {
            schema.object_type "Widget" do |t|
              t.field "id", "ID" do |f|
                f.resolve_with :get_record_field_value
              end
              t.index "widgets"
            end
          }
        )

        expect {
          graphql.schema
        }.to raise_error Errors::SchemaError, a_string_including(
          "Resolver `get_record_field_value`", "cannot be found."
        )
      end

      it "loads the GraphQL C parser for faster GraphQL parsing" do
        build_graphql.schema

        expect(::GraphQL.default_parser.name).to eq "GraphQL::CParser"
      end
    end

    describe "#load_dependencies_eagerly" do
      it "loads dependencies eagerly" do
        graphql = build_graphql

        expect(loaded_dependencies_of(graphql)).to exclude(:schema, :graphql_query_executor)
        graphql.load_dependencies_eagerly
        expect(loaded_dependencies_of(graphql)).to include(:schema, :graphql_query_executor)
      end

      def loaded_dependencies_of(graphql)
        graphql.instance_variables
          .reject { |ivar| graphql.instance_variable_get(ivar).nil? }
          .map { |ivar_name| ivar_name.to_s.delete_prefix("@").to_sym }
      end
    end

    context "when `config.extension_modules` or runtime metadata graphql extension modules are configured" do
      it "applies the extensions when the GraphQL instance is instantiated without impacting any other instances" do
        extension_data = {"extension" => "data"}

        config_extension_module = Module.new do
          define_method :graphql_schema_string do
            super() + "\n# #{extension_data.inspect}"
          end
        end
        stub_const("ConfigExtensionModule", config_extension_module)

        runtime_metadata_extension_module = Module.new do
          define_method :runtime_metadata do
            metadata = super()
            metadata.with(
              scalar_types_by_name: metadata.scalar_types_by_name.merge(extension_data)
            )
          end
        end
        stub_const("RuntimeMetadataExtensionModule", runtime_metadata_extension_module)

        extended_graphql = build_graphql(
          extension_modules: [config_extension_module],
          schema_definition: lambda do |schema|
            # `defined_at` just needs a valid require path, but needs to be outside ElasticGraph
            # to not mess with our code coverage measurement.
            schema.register_graphql_extension runtime_metadata_extension_module, defined_at: "time"
            define_schema_elements(schema)
          end
        )

        normal_graphql = build_graphql(
          schema_definition: lambda { |schema| define_schema_elements(schema) }
        )

        expect(extended_graphql.runtime_metadata.scalar_types_by_name).to include(extension_data)
        expect(extended_graphql.graphql_schema_string).to include(extension_data.inspect)

        expect(normal_graphql.runtime_metadata.scalar_types_by_name).not_to include(extension_data)
        expect(normal_graphql.graphql_schema_string).not_to include(extension_data.inspect)
      end

      def define_schema_elements(schema)
        schema.object_type "Widget" do |t|
          t.field "id", "ID!"
          t.index "widgets"
        end
      end
    end
  end
end
