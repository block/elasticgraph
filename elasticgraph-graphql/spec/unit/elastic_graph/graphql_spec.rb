# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql"
require "elastic_graph/graphql/resolvers/graphql_adapter"

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

    describe "#schema" do
      it "uses the injected `graphql_adapter` if provided" do
        graphql_adapter = instance_double(GraphQL::Resolvers::GraphQLAdapter).as_null_object

        # Manually stub these method; otherwise we get odd warnings like this:
        # /Users/myron/Development/sq-elasticgraph-ruby/bundle/ruby/2.7.0/gems/graphql-2.0.15/lib/graphql/schema/build_from_definition.rb:305: warning: #<Class:0x000000014c0cdad0>#coerce_result at /Users/myron/.rvm/rubies/ruby-2.7.5/lib/ruby/2.7.0/forwardable.rb:154 forwarding to private method RSpec::Mocks::InstanceVerifyingDouble#coerce_result
        #
        # I don't understand why are started getting these warnings but this fixes it.
        allow(graphql_adapter).to receive(:coerce_input) { |_, value, _| value }
        allow(graphql_adapter).to receive(:coerce_result) { |_, value, _| value }
      end

      it "uses a real normal `graphql_adapter` if none is provided" do
        expect(build_graphql.schema.send(:resolver)).to be_a ElasticGraph::GraphQL::Resolvers::GraphQLAdapter
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

        runtime_metadata_extension_module = Module.new do
          define_method :runtime_metadata do
            metadata = super()
            metadata.with(
              scalar_types_by_name: metadata.scalar_types_by_name.merge(extension_data)
            )
          end
        end

        extended_graphql = build_graphql(
          extension_modules: [config_extension_module],
          schema_definition: lambda do |schema|
            schema.register_graphql_extension runtime_metadata_extension_module, defined_at: __FILE__
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